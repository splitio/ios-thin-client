//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol EventSubmissionCoordinator: Sendable {
    /// If a submission is already running, new triggers should be dropped.
    func triggerSubmission(reason: EventsFlushReason) async
    /// When disabled (consent not granted), submissions are suppressed even if triggered.
    func setSubmissionEnabled(_ enabled: Bool)
}

final class DefaultEventSubmissionCoordinator: EventSubmissionCoordinator, @unchecked Sendable {

    private let eventTask: EventTask
    private let observer: Observer

    private var isSubmitting = false
    private var submissionEnabled = true
    private let lock = NSLock()

    init(eventTask: EventTask, observer: Observer) {
        self.eventTask = eventTask
        self.observer = observer
    }

    func setSubmissionEnabled(_ enabled: Bool) {
        withLock(lock) { submissionEnabled = enabled }
    }

    func triggerSubmission(reason: EventsFlushReason) async {
        let shouldRun = withLock(lock) {
            guard submissionEnabled else { return false }
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
