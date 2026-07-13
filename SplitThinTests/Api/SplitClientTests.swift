import XCTest
import Tracker
@testable import SplitThin

final class DefaultSplitClientTest: XCTestCase {

    private var client: DefaultSplitClient!
    private var treatmentsManagerMock: TreatmentsManagerMock!
    private var eventsManagerMock: SplitEventsManagerMock!
    private var authProviderMock: AuthProviderMock!
    private var syncManagerMock: SyncManagerMock!
    private var trackerMock: TrackerMock!
    private var eventsTrackerMock: EventsTrackerMock!
    private var eventsSchedulerMock: EventsPeriodicSchedulerMock!
    private var fetchCoordinatorMock: EvaluationFetchCoordinatorMock!

    override func setUp() {
        super.setUp()
        treatmentsManagerMock = TreatmentsManagerMock()
        eventsManagerMock = SplitEventsManagerMock()
        authProviderMock = AuthProviderMock()
        syncManagerMock = SyncManagerMock()
        trackerMock = TrackerMock()
        eventsTrackerMock = EventsTrackerMock()
        eventsSchedulerMock = EventsPeriodicSchedulerMock()
        fetchCoordinatorMock = EvaluationFetchCoordinatorMock()
        client = buildClient(target: "user1", treatmentsManager: treatmentsManagerMock, eventsManager: eventsManagerMock, authProvider: authProviderMock, syncManager: syncManagerMock, tracker: trackerMock, eventsTracker: eventsTrackerMock, eventsScheduler: eventsSchedulerMock, fetchCoordinator: fetchCoordinatorMock)
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
        client.setTarget(target: Target(matchingKey: "user2", trafficType: "user"))

        waitUntil { self.client.target.key.matchingKey == "user2" }
    }

    func testSetTargetReRegistersKeyForAuth() {
        client.setTarget(target: Target(matchingKey: "user2", trafficType: "user"))

        waitUntil { authProviderMock.lastTargetRegistered == "user2" }
        XCTAssertEqual(authProviderMock.lastTargetUnregistered, "user1", "Previous key must be unregistered")
    }

    func testSetTargetForwardsToSyncManager() {
        client.setTarget(target: Target(matchingKey: "user2", trafficType: "user"))

        waitUntil { self.syncManagerMock.setTargetCallCount == 1 }
        XCTAssertEqual(syncManagerMock.setTargetCallCount, 1)
        XCTAssertEqual(syncManagerMock.lastTargetSet?.matchingKey, "user2", "Background sync must move onto the new target")
    }

    func testSetTargetSameKeyDoesNotChurnAuth() {
        client.setTarget(target: Target(matchingKey: "user1", attributes: ["env": "prod"], trafficType: "user")) // same target

        waitUntil { self.syncManagerMock.setTargetCallCount == 1 }
        XCTAssertEqual(authProviderMock.registerCallCount, 0, "Re-targeting the same key must not re-register")
        XCTAssertEqual(authProviderMock.unregisterCallCount, 0, "Re-targeting the same key must not unregister")
    }

    func testSetTargetIdenticalIsNoOp() {
        client.setTarget(target: Target(matchingKey: "user1", trafficType: "user")) // exact same target
        client.setTarget(target: Target(matchingKey: "user2", trafficType: "user")) // different target

        waitUntil { self.syncManagerMock.lastTargetSet?.matchingKey == "user2" }
        XCTAssertEqual(syncManagerMock.setTargetCallCount, 1, "Identical setTarget must not propagate to syncManager")
        XCTAssertEqual(treatmentsManagerMock.setTargetCalls.count, 1, "Identical setTarget must not propagate to treatmentsManager")
    }

    func testSetTargetUnregistersOldTargetFromCoordinator() {
        client.setTarget(target: Target(matchingKey: "user2", trafficType: "user"))
        waitUntil { self.fetchCoordinatorMock.unregisterCalls.first?.matchingKey == "user1" }
    }

    func testSameKeyDiffBucketingUnregistersOldFromCoordinator() {
        client.setTarget(target: Target(matchingKey: "user1", bucketingKey: "bucket-2", trafficType: "user"))

        waitUntil {
            self.fetchCoordinatorMock.unregisterCalls.contains { $0.matchingKey == "user1" && $0.bucketingKey == nil }
        }
    }

    func testSameKeyDiffBucketingReRegistersUpdateAction() {
        client.setTarget(target: Target(matchingKey: "user1", bucketingKey: "bucket-2", trafficType: "user"))

        waitUntil {
            self.fetchCoordinatorMock.registerOnUpdateActionCalls.contains { $0.matchingKey == "user1" && $0.bucketingKey == "bucket-2" }
        }
    }

    func testTrafficTypeOnlyDoesNotUnregisterFromCoordinator() {
        // Only trafficType changes: no refetch, no coordinator churn.
        client.setTarget(target: Target(matchingKey: "user1", trafficType: "account"))

        waitUntil { self.syncManagerMock.setTargetCallCount == 1 }
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

    func testDestroyUnregistersTarget() async {
        await client.destroy()

        XCTAssertEqual(authProviderMock.unregisterCallCount, 1)
        XCTAssertEqual(authProviderMock.lastTargetUnregistered, "user1")
    }

    func testDestroyUnregistersTargetFromCoordinator() async {
        await client.destroy()

        XCTAssertTrue(fetchCoordinatorMock.unregisterCalls.contains { $0.matchingKey == "user1" },
                      "destroy() must unregister the target from the shared coordinator so streaming/polling stops refetching it")
    }

    func testDestroyUnregistersUpdateActionFromCoordinator() async {
        await client.destroy()

        XCTAssertTrue(fetchCoordinatorMock.unregisterOnUpdateActionCalls.contains { $0.matchingKey == "user1" },
                      "destroy() must remove the update action so shared refreshes stop notifying a dead client")
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

        let client2 = buildClient(target: "user2", treatmentsManager: treatmentsManagerMock, eventsManager: eventsManagerMock, syncManager: syncManagerMock)
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
