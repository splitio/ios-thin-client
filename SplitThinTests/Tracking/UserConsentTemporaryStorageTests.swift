//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import XCTest
@testable import SplitThin

final class UserConsentTemporaryStorageTest: XCTestCase {

    private var persistent: EventsStorageMock!

    override func setUp() {
        super.setUp()
        persistent = EventsStorageMock()
    }

    private func event(_ type: String) -> EventEntity {
        EventEntity(trafficType: "user", eventType: type)
    }

    // MARK: - Persistence disabled (unknown/declined)

    func testAddBuffersInMemoryWhenPersistenceDisabled() async {
        let storage = UserConsentTemporaryStorage(persistentStorage: persistent, persistenceEnabled: false)

        await storage.add(event("a"))
        await storage.add(event("b"))

        XCTAssertTrue(persistent.addedEvents.isEmpty, "Nothing should reach the persistent store while disabled")
    }

    func testEnablePersistenceFlushesBufferedEvents() async {
        let storage = UserConsentTemporaryStorage(persistentStorage: persistent, persistenceEnabled: false)
        await storage.add(event("a"))
        await storage.add(event("b"))

        await storage.enablePersistence(true)

        XCTAssertEqual(persistent.addedEvents.count, 2, "Buffered events must be flushed on grant")
        XCTAssertEqual(persistent.addedEvents.map { $0.eventType }, ["a", "b"])
    }

    func testClearInMemoryDiscardsBuffer() async {
        let storage = UserConsentTemporaryStorage(persistentStorage: persistent, persistenceEnabled: false)
        await storage.add(event("a"))

        await storage.clearInMemory()
        await storage.enablePersistence(true)

        XCTAssertTrue(persistent.addedEvents.isEmpty, "Discarded events must not be flushed")
    }

    func testBufferDropsOldestEventsWhenOverLimit() async {
        let storage = UserConsentTemporaryStorage(persistentStorage: persistent, persistenceEnabled: false)
        let overBy = 50
        let total = 10_000 + overBy
        await storage.add((0..<total).map { event("e-\($0)") })

        await storage.enablePersistence(true)

        XCTAssertEqual(persistent.addedEvents.count, 10_000, "Buffer must be capped at the limit")
        XCTAssertEqual(persistent.addedEvents.first?.eventType, "e-\(overBy)", "Oldest events must be the ones dropped")
        XCTAssertEqual(persistent.addedEvents.last?.eventType, "e-\(total - 1)")
    }

    // MARK: - Persistence enabled (granted)

    func testAddGoesStraightToPersistentWhenEnabled() async {
        let storage = UserConsentTemporaryStorage(persistentStorage: persistent, persistenceEnabled: true)

        await storage.add(event("a"))

        XCTAssertEqual(persistent.addedEvents.count, 1)
        XCTAssertEqual(persistent.addedEvents[0].eventType, "a")
    }

    func testDisableThenEnableFlushesOnlyEventsBufferedWhileDisabled() async {
        let storage = UserConsentTemporaryStorage(persistentStorage: persistent, persistenceEnabled: true)
        await storage.add(event("granted-1")) // straight through

        await storage.enablePersistence(false)
        await storage.add(event("buffered")) // buffered

        await storage.enablePersistence(true) // flush

        XCTAssertEqual(persistent.addedEvents.map { $0.eventType }, ["granted-1", "buffered"])
    }

    // MARK: - Reads delegate to persistent store

    func testReadsDelegateToPersistent() async {
        persistent.batchToReturn = [event("x")]
        persistent.countToReturn = 7
        let storage = UserConsentTemporaryStorage(persistentStorage: persistent, persistenceEnabled: true)

        let batch = await storage.getBatch(size: 10)
        let count = await storage.count()

        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(count, 7)
    }
}
