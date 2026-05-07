//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol EventTask: Sendable {
    func run() async -> Bool
}

final class DefaultEventTask: EventTask {

    private static let batchSize = 200

    private let storage: EventsReadStorage & EventsWriteStorage
    private let serializer: EventSerializer
    private let submitter: HttpEventsSubmitter
    private let observer: Observer
    private let target: Target

    init(storage: EventsReadStorage & EventsWriteStorage, serializer: EventSerializer, submitter: HttpEventsSubmitter, observer: Observer, target: Target) {
        self.storage = storage
        self.serializer = serializer
        self.submitter = submitter
        self.observer = observer
        self.target = target
    }

    func run() async -> Bool {
        var totalSent = 0

        while true {
            let batch = await storage.getBatch(size: Self.batchSize)
            guard !batch.isEmpty else { break }

            do {
                let payload = try serializer.serialize(batch)
                try await submitter.submit(payload: payload, target: target)
                await storage.remove(batch)
                totalSent += batch.count
            } catch {
                Logger.e("DefaultEventTask: Failed to submit \(batch.count) events")
                observer.notify(event: .eventsPostFailed)
                return false
            }
        }

        if totalSent > 0 {
            observer.notify(event: .eventsPostSucceeded(count: totalSent))
        }
        return true
    }
}
