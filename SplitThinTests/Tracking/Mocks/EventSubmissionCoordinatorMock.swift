import Foundation
@testable import SplitThin

final class EventSubmissionCoordinatorMock: EventSubmissionCoordinator, @unchecked Sendable {

    var triggerCalls = [EventsFlushReason]()
    var submissionEnabled = true

    func triggerSubmission(reason: EventsFlushReason) async {
        triggerCalls.append(reason)
    }

    func setSubmissionEnabled(_ enabled: Bool) {
        submissionEnabled = enabled
    }
}
