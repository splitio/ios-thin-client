//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol EventsTracker: Sendable {
    func track(_ event: EventEntity) async
    func flush() async
}

final class DefaultEventsTracker: EventsTracker, @unchecked Sendable {

    private static let queueSizeThreshold = 2000

    private let validator: EventsValidator
    private let storage: EventsWriteStorage & EventsReadStorage
    private let coordinator: EventSubmissionCoordinator
    private let observer: Observer

    init(validator: EventsValidator, storage: EventsWriteStorage & EventsReadStorage, coordinator: EventSubmissionCoordinator, observer: Observer) {
        self.validator = validator
        self.storage = storage
        self.coordinator = coordinator
        self.observer = observer
    }

    func track(_ event: EventEntity) async {
        guard validator.validate(event) else {
            observer.notify(event: .trackDropped(reason: .invalid))
            return
        }

        await storage.add(event)

        let currentCount = await storage.count()
        if currentCount >= Self.queueSizeThreshold {
            await coordinator.triggerSubmission(reason: .queue)
        }
    }

    func flush() async {
        await coordinator.triggerSubmission(reason: .flush)
    }
}
