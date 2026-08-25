//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import XCTest
@testable import SplitThin

final class DefaultUserConsentManagerTest: XCTestCase {

    private var storage: EventsConsentControllableMock!
    private var tracker: EventsTrackerMock!
    private var scheduler: EventsPeriodicSchedulerMock!
    private var coordinator: EventSubmissionCoordinatorMock!

    override func setUp() {
        super.setUp()
        storage = EventsConsentControllableMock()
        tracker = EventsTrackerMock()
        scheduler = EventsPeriodicSchedulerMock()
        coordinator = EventSubmissionCoordinatorMock()
    }

    private func makeManager(initial: UserConsent) -> DefaultUserConsentManager {
        DefaultUserConsentManager(initialStatus: initial)
    }

    private func bundle() -> ConsentControllableBundle {
        ConsentControllableBundle(storage: storage, tracker: tracker, scheduler: scheduler, coordinator: coordinator)
    }

    // MARK: - register applies the initial status

    func testRegisterWithUnknownTracksInMemoryOnly() async {
        let manager = makeManager(initial: .unknown)

        await manager.register(bundle())

        XCTAssertTrue(tracker.trackingEnabled, "Unknown must keep tracking on")
        XCTAssertEqual(storage.lastPersistenceValue, false, "Unknown must not persist")
        XCTAssertFalse(coordinator.submissionEnabled, "Unknown must not submit")
        XCTAssertEqual(scheduler.startCallCount, 0, "Unknown must not start the recorder")
    }

    func testRegisterWithGrantedStartsRecording() async {
        let manager = makeManager(initial: .granted)

        await manager.register(bundle())

        XCTAssertTrue(tracker.trackingEnabled)
        XCTAssertEqual(storage.lastPersistenceValue, true)
        XCTAssertTrue(coordinator.submissionEnabled)
        XCTAssertEqual(scheduler.startCallCount, 1)
    }

    // MARK: - Transitions

    func testSetGrantedEnablesPersistenceAndRecording() async {
        let manager = makeManager(initial: .unknown)
        await manager.register(bundle())

        await manager.set(.granted)

        let status = await manager.getStatus()
        XCTAssertEqual(status, .granted)
        XCTAssertTrue(tracker.trackingEnabled)
        XCTAssertEqual(storage.lastPersistenceValue, true, "Granting must flush/enable persistence")
        XCTAssertTrue(coordinator.submissionEnabled)
        XCTAssertEqual(scheduler.startCallCount, 1)
    }

    func testSetDeclinedStopsTrackingAndDiscards() async {
        let manager = makeManager(initial: .granted)
        await manager.register(bundle())

        await manager.set(.declined)

        let status = await manager.getStatus()
        XCTAssertEqual(status, .declined)
        XCTAssertFalse(tracker.trackingEnabled, "Declined must stop tracking")
        XCTAssertEqual(storage.lastPersistenceValue, false)
        XCTAssertFalse(coordinator.submissionEnabled)
        XCTAssertEqual(scheduler.stopCallCount, 1)
        XCTAssertEqual(storage.clearInMemoryCallCount, 1, "Declined must discard buffered events")
    }

    func testSetSameStatusIsNoOp() async {
        let manager = makeManager(initial: .granted)
        await manager.register(bundle()) // applies granted once

        let startsAfterRegister = scheduler.startCallCount
        let persistenceCallsAfterRegister = storage.enablePersistenceCalls.count

        await manager.set(.granted) // same status

        XCTAssertEqual(scheduler.startCallCount, startsAfterRegister, "Repeated status must not re-apply")
        XCTAssertEqual(storage.enablePersistenceCalls.count, persistenceCallsAfterRegister)
    }

    // MARK: - Fan-out and destroy

    func testSetFansOutToAllBundles() async {
        let storage2 = EventsConsentControllableMock()
        let tracker2 = EventsTrackerMock()
        let scheduler2 = EventsPeriodicSchedulerMock()
        let coordinator2 = EventSubmissionCoordinatorMock()

        let manager = makeManager(initial: .unknown)
        await manager.register(bundle())
        await manager.register(ConsentControllableBundle(storage: storage2, tracker: tracker2, scheduler: scheduler2, coordinator: coordinator2))

        await manager.set(.granted)

        XCTAssertEqual(scheduler.startCallCount, 1)
        XCTAssertEqual(scheduler2.startCallCount, 1)
        XCTAssertEqual(storage.lastPersistenceValue, true)
        XCTAssertEqual(storage2.lastPersistenceValue, true)
    }

    func testClearPendingDiscardsAllBuffers() async {
        let manager = makeManager(initial: .unknown)
        await manager.register(bundle())

        await manager.clearPending()

        XCTAssertEqual(storage.clearInMemoryCallCount, 1)
    }
}
