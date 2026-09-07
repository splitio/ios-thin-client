//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

enum EventTaskResult: Sendable {
    case success
    case failed
    case unauthorized
}

protocol EventTask: Sendable {
    func run() async -> EventTaskResult
}

final class DefaultEventTask: EventTask {

    private static let batchSize = 500

    private let storage: EventsReadStorage & EventsWriteStorage
    private let serializer: EventSerializer
    private let submitter: HttpEventsSubmitter
    private let observer: Observer

    init(storage: EventsReadStorage & EventsWriteStorage, serializer: EventSerializer, submitter: HttpEventsSubmitter, observer: Observer) {
        self.storage = storage
        self.serializer = serializer
        self.submitter = submitter
        self.observer = observer
    }

    func run() async -> EventTaskResult {
        var totalSent = 0

        while true {
            let batch = await storage.getBatch(size: Self.batchSize)
            guard !batch.isEmpty else { break }

            do {
                let payload = try serializer.serialize(batch)
                try await submitter.submit(payload: payload)
                await storage.remove(batch)
                totalSent += batch.count
            } catch CredentialFetcherError.unauthorized {
                Logger.e("DefaultEventTask: Unauthorized (401), stopping")
                observer.notify(event: .eventsPostFailed)
                return .unauthorized
            } catch {
                Logger.e("DefaultEventTask: Failed to submit \(batch.count) events")
                observer.notify(event: .eventsPostFailed)
                return .failed
            }
        }

        if totalSent > 0 {
            observer.notify(event: .eventsPostSucceeded(count: totalSent))
        }
        return .success
    }
}
