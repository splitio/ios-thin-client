import XCTest
import Http
@testable import SplitThin

final class PollingE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!

    override func setUp() {
        super.setUp()
        httpMock = SecureHttpClientMock()
    }

    override func tearDown() {
        httpMock = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testPollingFetchesPeriodically() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation(description: "SDK ready")
        let sdkUpdate = expectation(description: "SDK update")
        let listener = TestEventListener(onReadyExpectation: sdkReady, onUpdateExpectation: sdkUpdate)
        let factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady, sdkUpdate)

        let callCount = httpMock.fetchEvaluationsCalls.count
        XCTAssertGreaterThanOrEqual(callCount, 2, "Expected at least 2 fetches, got \(callCount)")

        await factory.destroy()
    }

    func testPollingUpdatesClientTreatments() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(onReadyExpectation: sdkReady)
        let factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let result = factory.client.getTreatment(flag: "my-flag")
        XCTAssertEqual(result.treatment, "on")

        await factory.destroy()
    }

    func testPollingStopsOnDestroy() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(onReadyExpectation: sdkReady)
        let factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
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

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(onReadyExpectation: sdkReady)
        let factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let callCount = httpMock.fetchEvaluationsCalls.count
        XCTAssertEqual(callCount, 1, "SingleSync should fetch exactly once, got \(callCount)")

        await factory.destroy()
    }
}
