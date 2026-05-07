import Foundation
@testable import SplitThin

final class HttpEventsSubmitterMock: HttpEventsSubmitter, @unchecked Sendable {

    var submitCalls = [(payload: Data, target: Target)]()
    var shouldThrow = false

    func submit(payload: Data, target: Target) async throws {
        submitCalls.append((payload, target))
        if shouldThrow { throw NSError(domain: "test", code: 1) }
    }
}
