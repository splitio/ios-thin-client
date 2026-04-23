import XCTest
import Http
@testable import SplitThin

final class EventsE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!
    private var factory: SplitFactory!

    override func setUp() {
        super.setUp()
        httpMock = SecureHttpClientMock()
    }

    override func tearDown() async throws {
        await factory?.destroy()
        factory = nil
        httpMock = nil
        try await super.tearDown()
    }

    // MARK: - SDK_READY

    func testSdkReadyFiresOnSuccessfulFetch() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertEqual(listener.onReadyCallCount, 1)
    }

    func testSdkReadyFiresWithEmptyEvaluations() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: []))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertEqual(listener.onReadyCallCount, 1)
    }

    func testSdkReadyMetadata() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertNotNil(listener.lastReadyMetadata)
        XCTAssertFalse(listener.lastReadyMetadata?.isInitialCacheLoad ?? true)
        XCTAssertEqual(listener.lastReadyMetadata?.lastUpdateTimestamp, 12345)
    }

    func testSdkReadyFiresOnlyOnce() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady, sdkUpdate)

        XCTAssertEqual(listener.onReadyCallCount, 1)
        XCTAssertGreaterThanOrEqual(listener.onUpdateCallCount, 1)
    }

    // MARK: - SDK_UPDATE

    func testSdkUpdateFiresOnPollingRefresh() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady, sdkUpdate)

        XCTAssertEqual(listener.onReadyCallCount, 1)
        XCTAssertGreaterThanOrEqual(listener.onUpdateCallCount, 1)
    }

    func testSdkUpdateMetadataContainsFlagNames() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["feature_a", "feature_b"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady, sdkUpdate)

        XCTAssertNotNil(listener.lastUpdateMetadata)
        XCTAssertEqual(listener.lastUpdateMetadata?.type, .flagsUpdate)

        let names = listener.lastUpdateMetadata?.names ?? []
        XCTAssertTrue(names.contains("feature_a"))
        XCTAssertTrue(names.contains("feature_b"))
    }

    // MARK: - SDK_READY_TIMED_OUT

    func testSdkReadyTimedOutWhenFetchFails() async throws {
        httpMock.errorToThrow = NSError(domain: "test", code: -1)

        let sdkTimedOut = expectation("SDK timed out")
        let listener = TestEventListener(timeoutExpectation: sdkTimedOut)
        factory = try buildFactory(httpClient: httpMock, timeout: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkTimedOut)

        XCTAssertEqual(listener.onReadyTimedOutCallCount, 1)
        XCTAssertEqual(listener.onReadyCallCount, 0)
    }

    func testSdkReadyTimedOutDoesNotFireIfAlreadyReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let sdkNotTimedOut = expectation("SDK timed out").inverted()
        let listener = TestEventListener(readyExpectation: sdkReady, timeoutExpectation: sdkNotTimedOut)
        factory = try buildFactory(httpClient: httpMock, timeout: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)
        waitFor(sdkNotTimedOut, timeout: 0.5)

        XCTAssertEqual(listener.onReadyCallCount, 1)
        XCTAssertEqual(listener.onReadyTimedOutCallCount, 0)
    }

    // MARK: - Listeners

    func testAddRemoveEventListenerViaClient() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkNotReady = expectation("SDK ready").inverted()
        let listener = TestEventListener(readyExpectation: sdkNotReady)
        factory = try buildFactory(httpClient: httpMock)
        let client = factory.client

        client.addEventListener(listener)
        client.removeEventListener(listener)

        waitFor(sdkNotReady, timeout: 0.5)

        XCTAssertEqual(listener.onReadyCallCount, 0)
    }

    // MARK: - Multiple Clients

    func testIndependentEventsForDifferentClients() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let ready1 = expectation("Client 1 ready")
        let ready2 = expectation("Client 2 ready")
        let listener1 = TestEventListener(readyExpectation: ready1)
        let listener2 = TestEventListener(readyExpectation: ready2)

        factory = try buildFactory(httpClient: httpMock, target: "user-A")
        let client2 = factory.getClient("user-B")

        factory.client.addEventListener(listener1)
        client2.addEventListener(listener2)

        waitFor(ready1, ready2)

        XCTAssertEqual(listener1.onReadyCallCount, 1)
        XCTAssertEqual(listener2.onReadyCallCount, 1)
    }

    func testMulticlientEventsAreIsolated() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let ready1 = expectation("Client 1 ready")
        let listener1 = TestEventListener(readyExpectation: ready1)

        factory = try buildFactory(httpClient: httpMock, target: "user-A")
        factory.client.addEventListener(listener1)

        waitFor(ready1)

        // Client 1 should be ready, client2 doesn't exist yet
        XCTAssertEqual(listener1.onReadyCallCount, 1)

        // Now create client2 and verify it gets its own SDK_READY
        let ready2 = expectation("Client 2 ready")
        let listener2 = TestEventListener(readyExpectation: ready2)
        let client2 = factory.getClient("user-B")
        client2.addEventListener(listener2)

        waitFor(ready2)

        XCTAssertEqual(listener1.onReadyCallCount, 1)
        XCTAssertEqual(listener2.onReadyCallCount, 1)
    }

    func testOneClientFailsOtherSucceeds() async throws {
        httpMock.fetchEvaluationsResultByKey["user-A"] = .failure(NSError(domain: "test", code: -1))
        httpMock.fetchEvaluationsResultByKey["user-B"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"])))

        let timedOut1 = expectation("Client 1 timed out")
        let ready2 = expectation("Client 2 ready")
        let listener1 = TestEventListener(timeoutExpectation: timedOut1)
        let listener2 = TestEventListener(readyExpectation: ready2)

        factory = try buildFactory(httpClient: httpMock, timeout: 1, target: "user-A")
        let client2 = factory.getClient("user-B")

        factory.client.addEventListener(listener1)
        client2.addEventListener(listener2)

        waitFor(ready2, timedOut1)

        // Client 1
        XCTAssertEqual(listener1.onReadyCallCount, 0)
        XCTAssertEqual(listener1.onReadyTimedOutCallCount, 1)

        // Client 2
        XCTAssertEqual(listener2.onReadyCallCount, 1)
        XCTAssertEqual(listener2.onReadyTimedOutCallCount, 0)
    }

    func testFirstUpdateDoesNotFireBeforeReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertEqual(listener.onReadyCallCount, 1)
        XCTAssertEqual(listener.onUpdateCallCount, 0)

        waitFor(sdkUpdate) // First polling cycle
    }

    func testMulticlientUpdatesAreIsolated() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let ready1 = expectation("Client 1 ready")
        let ready2 = expectation("Client 2 ready")
        let update1 = expectation("Client 1 update")
        let update2 = expectation("Client 2 update")
        let listener1 = TestEventListener(readyExpectation: ready1, updateExpectation: update1)
        let listener2 = TestEventListener(readyExpectation: ready2, updateExpectation: update2)

        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1, target: "user-A")
        let client2 = factory.getClient("user-B")

        factory.client.addEventListener(listener1)
        client2.addEventListener(listener2)

        waitFor(ready1, ready2, update1, update2)

        // Client 1
        XCTAssertEqual(listener1.onReadyCallCount, 1)
        XCTAssertGreaterThanOrEqual(listener1.onUpdateCallCount, 1)

        // Client 2
        XCTAssertEqual(listener2.onReadyCallCount, 1)
        XCTAssertGreaterThanOrEqual(listener2.onUpdateCallCount, 1)
    }

    // MARK: - Destroy

    func testDestroyStopsEventNotifications() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)
        await factory.destroy()

        let updateCountAfterDestroy = listener.onUpdateCallCount

        sleep(seconds: 1.2) // Give time to polling

        XCTAssertEqual(listener.onUpdateCallCount, updateCountAfterDestroy)
    }
}
