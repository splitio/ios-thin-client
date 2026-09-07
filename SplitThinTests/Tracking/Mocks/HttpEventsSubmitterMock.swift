import Foundation
@testable import SplitThin

final class HttpEventsSubmitterMock: HttpEventsSubmitter, @unchecked Sendable {

    var submitCalls = [Data]()
    var shouldThrow = false

    func submit(payload: Data) async throws {
        submitCalls.append(payload)
        if shouldThrow { throw NSError(domain: "test", code: 1) }
    }
}
