import Foundation
@testable import SplitThin

final class EventsValidatorMock: EventsValidator, @unchecked Sendable {

    var validateResult = true
    var validateCalls = [EventEntity]()

    func validate(_ event: EventEntity) -> Bool {
        validateCalls.append(event)
        return validateResult
    }
}
