import Foundation
@testable import SplitThin

final class EventsStorageMock: EventsReadStorage, EventsWriteStorage, @unchecked Sendable {

    var addedEvents = [EventEntity]()
    var removedEvents = [[EventEntity]]()
    var clearCalled = false
    var batchToReturn = [EventEntity]()
    var countToReturn = 0

    func add(_ event: EventEntity) async {
        addedEvents.append(event)
    }

    func add(_ events: [EventEntity]) async {
        addedEvents.append(contentsOf: events)
    }

    func remove(_ events: [EventEntity]) async {
        removedEvents.append(events)
    }

    func clear() async {
        clearCalled = true
    }

    func getBatch(size: Int) async -> [EventEntity] {
        let result = Array(batchToReturn.prefix(size))
        batchToReturn = Array(batchToReturn.dropFirst(size))
        return result
    }

    func count() async -> Int {
        countToReturn
    }
}
