import XCTest
import Http
@testable import SplitThin

final class PollingE2ETest: XCTestCase {

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

    // MARK: - Tests

    func testPollingFetchesPeriodically() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady, sdkUpdate)

        let callCount = httpMock.fetchEvaluationsCalls.count
        XCTAssertGreaterThanOrEqual(callCount, 2, "Expected at least 2 fetches, got \(callCount)")
    }

    func testPollingUpdatesClientTreatments() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let result = factory.client.getTreatment("my-flag")
        XCTAssertEqual(result.treatment, "on")
    }

    func testPollingStopsOnDestroy() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)
        await factory.destroy()

        let callCountAfterDestroy = httpMock.fetchEvaluationsCalls.count

        sleep(seconds: 1.5) // Give time to verify no more fetches

        let callCountLater = httpMock.fetchEvaluationsCalls.count
        XCTAssertEqual(callCountAfterDestroy, callCountLater, "No more fetches should occur after destroy")
    }

    func testSingleSyncOnlyFetchesOnce() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let callCount = httpMock.fetchEvaluationsCalls.count
        XCTAssertEqual(callCount, 1, "SingleSync should fetch exactly once, got \(callCount)")
    }

    // MARK: - SDK_UPDATE via Polling

    func testSdkReadyFiresOnlyOnce() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady, sdkUpdate)

        XCTAssertEqual(listener.onReadyCallCount, 1)
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

    func testFirstUpdateDoesNotFireBeforeReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertEqual(listener.onUpdateCallCount, 0)

        waitFor(sdkUpdate) // First polling cycle
    }

    func testPollingUpdatesRepository() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"], treatment: "v1"))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertEqual(factory.client.getTreatment("my-flag").treatment, "v1")

        // Change the response before the next polling cycle
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"], treatment: "v2"))

        waitFor(sdkUpdate)

        XCTAssertEqual(factory.client.getTreatment("my-flag").treatment, "v2")
    }

    // MARK: - Multi-Client Polling Updates

    func testMulticlientUpdatesAreIsolated() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let ready1 = expectation("Client 1 ready")
        let ready2 = expectation("Client 2 ready")
        let update1 = expectation("Client 1 update")
        let update2 = expectation("Client 2 update")
        let listener1 = TestEventListener(readyExpectation: ready1, updateExpectation: update1)
        let listener2 = TestEventListener(readyExpectation: ready2, updateExpectation: update2)

        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1, target: Target(matchingKey: "user-A", trafficType: "user"))
        let client2 = factory.getClient("user-B")

        factory.client.addEventListener(listener1)
        client2.addEventListener(listener2)

        waitFor(ready1, ready2, update1, update2)
    }
}
