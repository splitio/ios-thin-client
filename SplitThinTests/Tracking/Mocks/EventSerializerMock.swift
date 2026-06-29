import Foundation
@testable import SplitThin

final class EventSerializerMock: EventSerializer, @unchecked Sendable {

    var serializeCalls = [[EventEntity]]()
    var dataToReturn = Data()
    var shouldThrow = false

    func serialize(_ events: [EventEntity]) throws -> Data {
        serializeCalls.append(events)
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        return dataToReturn
    }
}
