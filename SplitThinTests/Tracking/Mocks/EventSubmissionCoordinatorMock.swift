import Foundation
@testable import SplitThin

final class EventSubmissionCoordinatorMock: EventSubmissionCoordinator, @unchecked Sendable {

    var triggerCalls = [EventsFlushReason]()

    func triggerSubmission(reason: EventsFlushReason) async {
        triggerCalls.append(reason)
    }
}
