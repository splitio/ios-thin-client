import XCTest
@testable import SplitThin

final class DefaultSplitClientTest: XCTestCase {

    private var client: DefaultSplitClient!
    private var treatmentsManagerMock: TreatmentsManagerMock!
    private var eventsManagerMock: SplitEventsManagerMock!
    private var authProviderMock: AuthProviderMock!

    override func setUp() {
        super.setUp()
        treatmentsManagerMock = TreatmentsManagerMock()
        eventsManagerMock = SplitEventsManagerMock()
        authProviderMock = AuthProviderMock()
        client = DefaultSplitClient(target: Target(matchingKey: "user1"), treatmentsManager: treatmentsManagerMock, eventsManager: eventsManagerMock, authProvider: authProviderMock)
    }

    override func tearDown() {
        client = nil
        treatmentsManagerMock = nil
        eventsManagerMock = nil
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

    func testDestroyUnregistersTarget() async {
        await client.destroy()

        XCTAssertEqual(authProviderMock.unregisterCallCount, 1)
        XCTAssertEqual(authProviderMock.lastTargetUnregistered, "user1")
    }

    func testDestroyOnlyRemovesOwnListeners() async {
        let listener1 = TestEventListener()
        let listener2 = TestEventListener()
        client.addEventListener(listener1)

        let client2 = DefaultSplitClient(target: Target(matchingKey: "user2"), treatmentsManager: treatmentsManagerMock, eventsManager: eventsManagerMock, authProvider: AuthProviderMock())
        client2.addEventListener(listener2)

        await client.destroy()

        XCTAssertEqual(eventsManagerMock.removedListeners.count, 1)
    }
}
