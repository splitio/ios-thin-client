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
        DefaultUserConsentManager(initialStatus: initial, storage: storage, tracker: tracker, scheduler: scheduler, coordinator: coordinator)
    }

    // MARK: - start applies the initial status

    func testStartWithUnknownTracksInMemoryOnly() async {
        let manager = makeManager(initial: .unknown)

        await manager.start()

        XCTAssertEqual(tracker.trackingEnabled, true, "Unknown must keep tracking on")
        XCTAssertEqual(storage.lastPersistenceValue, false, "Unknown must not persist")
        XCTAssertEqual(coordinator.submissionEnabled, false, "Unknown must not submit")
        XCTAssertEqual(scheduler.startCallCount, 0, "Unknown must not start the recorder")
    }

    func testStartWithGrantedStartsRecording() async {
        let manager = makeManager(initial: .granted)

        await manager.start()

        XCTAssertEqual(tracker.trackingEnabled, true)
        XCTAssertEqual(storage.lastPersistenceValue, true)
        XCTAssertEqual(coordinator.submissionEnabled, true)
        XCTAssertEqual(scheduler.startCallCount, 1)
    }

    // MARK: - Transitions

    func testSetGrantedEnablesPersistenceAndRecording() async {
        let manager = makeManager(initial: .unknown)
        await manager.start()

        await manager.set(.granted)

        XCTAssertEqual(tracker.trackingEnabled, true)
        XCTAssertEqual(storage.lastPersistenceValue, true, "Granting must flush/enable persistence")
        XCTAssertEqual(coordinator.submissionEnabled, true)
        XCTAssertEqual(scheduler.startCallCount, 1)
    }

    func testSetDeclinedStopsTrackingAndDiscards() async {
        let manager = makeManager(initial: .granted)
        await manager.start()

        await manager.set(.declined)

        XCTAssertEqual(tracker.trackingEnabled, false, "Declined must stop tracking")
        XCTAssertEqual(storage.lastPersistenceValue, false)
        XCTAssertEqual(coordinator.submissionEnabled, false)
        XCTAssertEqual(scheduler.stopCallCount, 1)
        XCTAssertEqual(storage.clearInMemoryCallCount, 1, "Declined must discard buffered events")
    }

    func testSetSameStatusIsNoOp() async {
        let manager = makeManager(initial: .granted)
        await manager.start() // applies granted once

        let startsAfterStart = scheduler.startCallCount
        let persistenceCallsAfterStart = storage.enablePersistenceCalls.count

        await manager.set(.granted) // same status

        XCTAssertEqual(scheduler.startCallCount, startsAfterStart, "Repeated status must not re-apply")
        XCTAssertEqual(storage.enablePersistenceCalls.count, persistenceCallsAfterStart)
    }

    // MARK: - Reentrancy

    func testGrantSupersededByDeclineDoesNotEnableSubmission() async {
        let manager = makeManager(initial: .unknown)
        await manager.start()

        // Hold the grant inside the persistence flush so the decline lands while it is suspended.
        let flushStarted = expectation("grant reached the persistence flush")
        let flushGate = Gate()
        storage.onEnablePersistence = { enable in
            guard enable else { return }
            flushStarted.fulfill()
            await flushGate.wait()
        }

        let grant = Task { await manager.set(.granted) }
        await fulfillment(of: [flushStarted], timeout: 3)

        await manager.set(.declined)
        await flushGate.open()
        await grant.value

        XCTAssertEqual(coordinator.submissionEnabled, false, "A superseded grant must not enable submission")
        XCTAssertEqual(scheduler.startCallCount, 0, "A superseded grant must not start the recorder")
        XCTAssertEqual(tracker.trackingEnabled, false, "Declined must win")
    }

    // MARK: - Destroy

    func testClearPendingDiscardsBuffer() async {
        let manager = makeManager(initial: .unknown)
        await manager.start()

        await manager.clearPending()

        XCTAssertEqual(storage.clearInMemoryCallCount, 1)
    }
}

/// One-shot async gate so a test can park a suspension point and release it on demand.
private actor Gate {

    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
