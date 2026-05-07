import XCTest
import Tracker
@testable import SplitThin

final class DefaultSplitClientTest: XCTestCase {

    private var client: DefaultSplitClient!
    private var treatmentsManagerMock: TreatmentsManagerMock!
    private var eventsManagerMock: SplitEventsManagerMock!
    private var syncManagerMock: SyncManagerMock!
    private var trackerMock: TrackerMock!
    private var eventsTrackerMock: EventsTrackerMock!
    private var eventsSchedulerMock: EventsPeriodicSchedulerMock!

    override func setUp() {
        super.setUp()
        treatmentsManagerMock = TreatmentsManagerMock()
        eventsManagerMock = SplitEventsManagerMock()
        syncManagerMock = SyncManagerMock()
        trackerMock = TrackerMock()
        eventsTrackerMock = EventsTrackerMock()
        eventsSchedulerMock = EventsPeriodicSchedulerMock()
        client = DefaultSplitClient(target: Target(matchingKey: "user1"), treatmentsManager: treatmentsManagerMock, eventsManager: eventsManagerMock, observer: ObserverSpy(), syncManager: syncManagerMock, tracker: trackerMock, eventsTracker: eventsTrackerMock, eventsScheduler: eventsSchedulerMock)
    }

    override func tearDown() {
        client = nil
        treatmentsManagerMock = nil
        eventsManagerMock = nil
        syncManagerMock = nil
        eventsTrackerMock = nil
        eventsSchedulerMock = nil
        super.tearDown()
    }

    func testSetTargetUpdatesTarget() {
        client.setTarget(target: Target(matchingKey: "user2"))

        XCTAssertEqual(client.target.key.matchingKey, "user2")
    }

    func testGetTreatmentReturnsControl() {
        let result = client.getTreatment("flag_a")

        XCTAssertEqual(result.treatment, "control")
    }

    func testGetTreatmentsReturnsControlForAll() {
        let results = client.getTreatments(flags: ["flag_a", "flag_b"])

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.treatment == "control" })
    }

    func testDestroyIsIdempotent() async {
        await client.destroy()
        await client.destroy()
    }

    // MARK: - Event Listener Management

    func testAddEventListenerForwardsToEventsManager() {
        let listener = TestEventListener()

        client.addEventListener(listener)

        XCTAssertEqual(eventsManagerMock.addedListeners.count, 1)
    }

    func testRemoveEventListenerForwardsToEventsManager() {
        let listener = TestEventListener()
        client.addEventListener(listener)

        client.removeEventListener(listener)

        XCTAssertEqual(eventsManagerMock.removedListeners.count, 1)
    }

    func testDestroyRemovesAllClientListenersFromManager() async {
        let listener1 = TestEventListener()
        let listener2 = TestEventListener()
        client.addEventListener(listener1)
        client.addEventListener(listener2)

        await client.destroy()

        XCTAssertEqual(eventsManagerMock.removedListeners.count, 2)
    }

    func testDestroyStopsEventsManager() async {
        await client.destroy()

        XCTAssertEqual(eventsManagerMock.stopCallCount, 1)
    }

    func testDestroyStopsSyncManager() async {
        await client.destroy()

        XCTAssertEqual(syncManagerMock.stopCallCount, 1)
    }

    func testDestroyOnlyRemovesOwnListeners() async {
        let listener1 = TestEventListener()
        let listener2 = TestEventListener()
        client.addEventListener(listener1)

        let client2 = DefaultSplitClient(target: Target(matchingKey: "user2"), treatmentsManager: treatmentsManagerMock, eventsManager: eventsManagerMock, observer: ObserverSpy(), syncManager: syncManagerMock, tracker: TrackerMock(), eventsTracker: EventsTrackerMock(), eventsScheduler: EventsPeriodicSchedulerMock())
        client2.addEventListener(listener2)

        await client.destroy()

        XCTAssertEqual(eventsManagerMock.removedListeners.count, 1)
    }

    // MARK: - Tracking

    func testTrackDelegatesToTracker() {
        client.track(eventType: "purchase", value: 12.5, properties: ["plan": "pro"])

        XCTAssertEqual(trackerMock.trackCalls.count, 1)
        XCTAssertEqual(trackerMock.trackCalls[0].eventType, "purchase")
        XCTAssertEqual(trackerMock.trackCalls[0].value, 12.5)
        XCTAssertEqual(trackerMock.trackCalls[0].matchingKey, "user1")
    }

    func testTrackAfterDestroyDoesNotDelegate() async {
        await client.destroy()

        client.track(eventType: "purchase", value: nil, properties: nil)

        XCTAssertEqual(trackerMock.trackCalls.count, 0)
    }

    func testFlushDelegatesToEventsTracker() async {
        await client.flush()

        XCTAssertEqual(eventsTrackerMock.flushCallCount, 1)
    }

    func testDestroyStopsSchedulerAndFlushes() async {
        await client.destroy()

        XCTAssertEqual(eventsSchedulerMock.stopCallCount, 1)
        XCTAssertEqual(eventsTrackerMock.flushCallCount, 1)
    }
}
