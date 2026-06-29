//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol EventSubmissionCoordinator: Sendable {
    /// If a submission is already running, new triggers should be dropped.
    func triggerSubmission(reason: EventsFlushReason) async
}

final class DefaultEventSubmissionCoordinator: EventSubmissionCoordinator, @unchecked Sendable {

    private let eventTask: EventTask
    private let observer: Observer

    private var isSubmitting = false
    private let lock = NSLock()

    init(eventTask: EventTask, observer: Observer) {
        self.eventTask = eventTask
        self.observer = observer
    }

    func triggerSubmission(reason: EventsFlushReason) async {
        let shouldRun = withLock(lock) {
            guard !isSubmitting else { return false }
            isSubmitting = true
            return true
        }

        guard shouldRun else {
            Logger.d("DefaultEventSubmissionCoordinator: Submission skipped (\(reason))")
            return
        }

        observer.notify(event: .eventsFlushTriggered(reason: reason))
        let result = await eventTask.run()

        if result == .unauthorized {
            Logger.e("DefaultEventSubmissionCoordinator: Unauthorized (401)")
            observer.notify(event: .authUnauthorized)
            return
        }

        withLock(lock) { isSubmitting = false }
    }
}
