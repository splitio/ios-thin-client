//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol EventsTracker: Sendable {
    func track(_ event: EventEntity) async
    func flush() async
}

final class DefaultEventsTracker: EventsTracker, @unchecked Sendable {

    private static let queueSizeThreshold = 5000
    
    // Tracked events are accumulated and persisted in a single Core Data write,
    // instead of opening one context per event. This protects the store when the
    // consumer tracks a high volume of events in a tight loop. The buffer is drained
    // whenever either criterion is met: the time window elapses, or it fills up.
    private static let accumulationWindowNanos: UInt64 = 100_000_000
    private static let maxBufferSize = 500

    private let storage: EventsWriteStorage & EventsReadStorage
    private let coordinator: EventSubmissionCoordinator
    private let observer: Observer

    private var buffer = [EventEntity]()
    private let bufferLock = NSLock()
    private var windowTask: Task<Void, Never>?

    init(storage: EventsWriteStorage & EventsReadStorage, coordinator: EventSubmissionCoordinator, observer: Observer) {
        self.storage = storage
        self.coordinator = coordinator
        self.observer = observer
    }

    // Validation happens upstream in DefaultTracker (Tracker module) before events reach this point.
    // Events are buffered and written in batches; the periodic submission is handled by the worker.
    func track(_ event: EventEntity) async {
        let shouldFlushNow = withLock(bufferLock) {
            buffer.append(event)
            // The buffer is full: drain it immediately rather than waiting for the window.
            if buffer.count >= Self.maxBufferSize {
                return true
            }
            // Open a write window on the first event. While it's open, every event
            // that arrives is captured into the same buffer and written together.
            if windowTask == nil {
                windowTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: Self.accumulationWindowNanos)
                    await self?.flushBuffer()
                }
            }
            return false
        }

        if shouldFlushNow {
            await flushBuffer()
        }
    }

    func flush() async {
        await flushBuffer()
        await coordinator.triggerSubmission(reason: .flush)
    }

    private func flushBuffer() async {
        // Closing the window here means any event arriving during the write below
        // lands in a fresh buffer and opens a new window.
        let eventsToWrite: [EventEntity] = withLock(bufferLock) {
            windowTask?.cancel()
            windowTask = nil
            let events = buffer
            buffer.removeAll()
            return events
        }

        guard !eventsToWrite.isEmpty else { return }

        await storage.add(eventsToWrite)

        let currentCount = await storage.count()
        if currentCount >= Self.queueSizeThreshold {
            await coordinator.triggerSubmission(reason: .queue)
        }
    }
}
