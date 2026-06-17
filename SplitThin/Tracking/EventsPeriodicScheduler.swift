//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol EventsPeriodicScheduler: Sendable {
    func start()
    func stop()
}

final class DefaultEventsPeriodicScheduler: EventsPeriodicScheduler, @unchecked Sendable {

    private let coordinator: EventSubmissionCoordinator
    private let intervalSeconds: Int

    private var task: Task<Void, Never>?
    private var isRunning = false
    private let lock = NSLock()

    init(coordinator: EventSubmissionCoordinator, intervalSeconds: Int) {
        self.coordinator = coordinator
        self.intervalSeconds = intervalSeconds
    }

    func start() {
        withLock(lock) {
            guard !isRunning else { return }
            isRunning = true
        }

        task = Task { [weak self] in
            guard let self else {
                Logger.d("EventsPeriodicScheduler: self was deallocated, exiting")
                return
            }

            while !Task.isCancelled {
                let shouldRun = withLock(self.lock) { self.isRunning }
                guard shouldRun else {
                    Logger.d("EventsPeriodicScheduler: isRunning=false, exiting loop")
                    break
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(self.intervalSeconds) * 1_000_000_000)
                } catch {
                    break
                }

                await self.coordinator.triggerSubmission(reason: .interval)
            }
        }

        Logger.d("EventsPeriodicScheduler: Started with interval \(intervalSeconds)s")
    }

    func stop() {
        withLock(lock) {
            isRunning = false
        }
        task?.cancel()
        task = nil

        Logger.d("EventsPeriodicScheduler: Stopped")
    }
}
