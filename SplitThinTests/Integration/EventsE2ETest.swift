import XCTest
import Http
@testable import SplitThin

final class EventsE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!

    override func setUp() {
        super.setUp()
        httpMock = SecureHttpClientMock()
    }

    override func tearDown() {
        httpMock = nil
        super.tearDown()
    }

    // MARK: - SDK_READY

    func testSdkReadyFiresOnSuccessfulFetch() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(onReadyExpectation: sdkReady)
        let factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertEqual(listener.onReadyCallCount, 1)

        await factory.destroy()
    }

    func testSdkReadyFiresWithEmptyEvaluations() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: []))

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(onReadyExpectation: sdkReady)
        let factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertEqual(listener.onReadyCallCount, 1)

        await factory.destroy()
    }

    func testSdkReadyMetadata() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(onReadyExpectation: sdkReady)
        let factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertNotNil(listener.lastReadyMetadata)
        XCTAssertFalse(listener.lastReadyMetadata?.isInitialCacheLoad ?? true)
        XCTAssertNil(listener.lastReadyMetadata?.lastUpdateTimestamp)

        await factory.destroy()
    }

    func testSdkReadyFiresOnlyOnce() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation(description: "SDK ready")
        let sdkUpdate = expectation(description: "SDK update")
        let listener = TestEventListener(onReadyExpectation: sdkReady, onUpdateExpectation: sdkUpdate)
        let factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady, sdkUpdate)

        XCTAssertEqual(listener.onReadyCallCount, 1)
        XCTAssertGreaterThanOrEqual(listener.onUpdateCallCount, 1)

        await factory.destroy()
    }

    // MARK: - SDK_UPDATE

    func testSdkUpdateFiresOnPollingRefresh() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation(description: "SDK ready")
        let sdkUpdate = expectation(description: "SDK update")
        let listener = TestEventListener(onReadyExpectation: sdkReady, onUpdateExpectation: sdkUpdate)
        let factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady, sdkUpdate)

        XCTAssertEqual(listener.onReadyCallCount, 1)
        XCTAssertGreaterThanOrEqual(listener.onUpdateCallCount, 1)

        await factory.destroy()
    }

    func testSdkUpdateMetadataContainsFlagNames() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["feature_a", "feature_b"]))

        let sdkReady = expectation(description: "SDK ready")
        let sdkUpdate = expectation(description: "SDK update")
        let listener = TestEventListener(onReadyExpectation: sdkReady, onUpdateExpectation: sdkUpdate)
        let factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady, sdkUpdate)

        XCTAssertNotNil(listener.lastUpdateMetadata)
        XCTAssertEqual(listener.lastUpdateMetadata?.type, .flagsUpdate)

        let names = listener.lastUpdateMetadata?.names ?? []
        XCTAssertTrue(names.contains("feature_a"))
        XCTAssertTrue(names.contains("feature_b"))

        await factory.destroy()
    }

    // MARK: - SDK_READY_TIMED_OUT

    func testSdkReadyTimedOutWhenFetchFails() async throws {
        httpMock.errorToThrow = NSError(domain: "test", code: -1)

        let sdkTimedOut = expectation(description: "SDK timed out")
        let listener = TestEventListener(onTimedOutExpectation: sdkTimedOut)
        let factory = try buildFactory(httpClient: httpMock, timeout: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkTimedOut)

        XCTAssertEqual(listener.onReadyTimedOutCallCount, 1)
        XCTAssertEqual(listener.onReadyCallCount, 0)

        await factory.destroy()
    }

    func testSdkReadyTimedOutDoesNotFireIfAlreadyReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation(description: "SDK ready")
        let timeout = expectation(description: "SDK timed out")
        timeout.isInverted = true
        let listener = TestEventListener(onReadyExpectation: sdkReady, onTimedOutExpectation: timeout)
        let factory = try buildFactory(httpClient: httpMock, timeout: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)
        waitFor(timeout, timeout: 0.5)

        XCTAssertEqual(listener.onReadyCallCount, 1)
        XCTAssertEqual(listener.onReadyTimedOutCallCount, 0)

        await factory.destroy()
    }

    // MARK: - Listeners

    func testAddRemoveEventListenerViaClient() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation(description: "SDK ready")
        sdkReady.isInverted = true
        let listener = TestEventListener(onReadyExpectation: sdkReady)
        let factory = try buildFactory(httpClient: httpMock)
        let client = factory.client

        client.addEventListener(listener)
        client.removeEventListener(listener)

        waitFor(sdkReady, timeout: 0.5)

        XCTAssertEqual(listener.onReadyCallCount, 0)

        await factory.destroy()
    }

    // MARK: - Multiple Clients

    func testIndependentEventsForDifferentClients() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let ready1 = expectation(description: "Client 1 ready")
        let ready2 = expectation(description: "Client 2 ready")
        let listener1 = TestEventListener(onReadyExpectation: ready1)
        let listener2 = TestEventListener(onReadyExpectation: ready2)

        let factory = try buildFactory(httpClient: httpMock, target: Target(matchingKey: "user-A"))
        let client2 = factory.getClient(Target(matchingKey: "user-B"))

        factory.client.addEventListener(listener1)
        client2.addEventListener(listener2)

        waitFor(ready1, ready2)

        XCTAssertEqual(listener1.onReadyCallCount, 1)
        XCTAssertEqual(listener2.onReadyCallCount, 1)

        await factory.destroy()
    }

    func testMulticlientEventsAreIsolated() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let ready1 = expectation(description: "Client 1 ready")
        let listener1 = TestEventListener(onReadyExpectation: ready1)

        let factory = try buildFactory(httpClient: httpMock, target: Target(matchingKey: "user-A"))
        factory.client.addEventListener(listener1)

        waitFor(ready1)

        // Client 1 should be ready, client2 doesn't exist yet
        XCTAssertEqual(listener1.onReadyCallCount, 1)

        // Now create client2 and verify it gets its own SDK_READY
        let ready2 = expectation(description: "Client 2 ready")
        let listener2 = TestEventListener(onReadyExpectation: ready2)
        let client2 = factory.getClient(Target(matchingKey: "user-B"))
        client2.addEventListener(listener2)

        waitFor(ready2)

        XCTAssertEqual(listener1.onReadyCallCount, 1)
        XCTAssertEqual(listener2.onReadyCallCount, 1)

        await factory.destroy()
    }

    func testOneClientFailsOtherSucceeds() async throws {
        httpMock.fetchEvaluationsResultByKey["user-A"] = .failure(NSError(domain: "test", code: -1))
        httpMock.fetchEvaluationsResultByKey["user-B"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"])))

        let timedOut1 = expectation(description: "Client 1 timed out")
        let ready2 = expectation(description: "Client 2 ready")
        let listener1 = TestEventListener(onTimedOutExpectation: timedOut1)
        let listener2 = TestEventListener(onReadyExpectation: ready2)

        let factory = try buildFactory(httpClient: httpMock, timeout: 1, target: Target(matchingKey: "user-A"))
        let client2 = factory.getClient(Target(matchingKey: "user-B"))

        factory.client.addEventListener(listener1)
        client2.addEventListener(listener2)

        waitFor(ready2, timedOut1)

        // Client 1
        XCTAssertEqual(listener1.onReadyCallCount, 0)
        XCTAssertEqual(listener1.onReadyTimedOutCallCount, 1)

        // Client 2
        XCTAssertEqual(listener2.onReadyCallCount, 1)
        XCTAssertEqual(listener2.onReadyTimedOutCallCount, 0)

        await factory.destroy()
    }

    func testFirstUpdateDoesNotFireBeforeReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation(description: "SDK ready")
        let sdkUpdate = expectation(description: "SDK update")
        let listener = TestEventListener(onReadyExpectation: sdkReady, onUpdateExpectation: sdkUpdate)
        let factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertEqual(listener.onReadyCallCount, 1)
        XCTAssertEqual(listener.onUpdateCallCount, 0)

        waitFor(sdkUpdate) // First polling cycle

        await factory.destroy()
    }

    func testMulticlientUpdatesAreIsolated() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let ready1 = expectation(description: "Client 1 ready")
        let ready2 = expectation(description: "Client 2 ready")
        let update1 = expectation(description: "Client 1 update")
        let update2 = expectation(description: "Client 2 update")
        let listener1 = TestEventListener(onReadyExpectation: ready1, onUpdateExpectation: update1)
        let listener2 = TestEventListener(onReadyExpectation: ready2, onUpdateExpectation: update2)

        let factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1, target: Target(matchingKey: "user-A"))
        let client2 = factory.getClient(Target(matchingKey: "user-B"))

        factory.client.addEventListener(listener1)
        client2.addEventListener(listener2)

        waitFor(ready1, ready2, update1, update2)

        // Client 1
        XCTAssertEqual(listener1.onReadyCallCount, 1)
        XCTAssertGreaterThanOrEqual(listener1.onUpdateCallCount, 1)

        // Client 2
        XCTAssertEqual(listener2.onReadyCallCount, 1)
        XCTAssertGreaterThanOrEqual(listener2.onUpdateCallCount, 1)

        await factory.destroy()
    }

    // MARK: - Destroy

    func testDestroyStopsEventNotifications() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(onReadyExpectation: sdkReady)
        let factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)
        await factory.destroy()

        let updateCountAfterDestroy = listener.onUpdateCallCount

        sleep(seconds: 1.2) // Give time to polling

        XCTAssertEqual(listener.onUpdateCallCount, updateCountAfterDestroy)

        await factory.destroy()
    }
}
