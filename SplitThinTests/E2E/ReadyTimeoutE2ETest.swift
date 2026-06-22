import XCTest
import Http
@testable import SplitThin

final class ReadyTimeoutE2ETest: XCTestCase {

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

    // MARK: - Unit tests (no waiting)

    func testReadyTimeoutDefaultIs10() {
        let config = SplitClientConfig.builder().build()
        XCTAssertEqual(config.readyTimeout, 10)
    }

    func testReadyTimeoutZeroResetsToDefault() {
        let config = SplitClientConfig.builder().set(readyTimeout: 0).build()
        XCTAssertEqual(config.readyTimeout, 10)
    }

    func testReadyTimeoutNegativeResetsToDefault() {
        let config = SplitClientConfig.builder().set(readyTimeout: -5).build()
        XCTAssertEqual(config.readyTimeout, 10)
    }

    func testReadyTimeoutMinusOneIsAccepted() {
        let config = SplitClientConfig.builder().set(readyTimeout: -1).build()
        XCTAssertEqual(config.readyTimeout, -1)
    }

    func testReadyTimeoutPositiveIsAccepted() {
        let config = SplitClientConfig.builder().set(readyTimeout: 30).build()
        XCTAssertEqual(config.readyTimeout, 30)
    }

    // MARK: - E2E test

    func testReadyTimeoutFiresBeforeServerResponds() async throws {
        httpMock.fetchDelay = 3_000_000_000
        httpMock.fetchEvaluationsResult = HttpResponse(
            code: 200,
            data: mockEvaluationsData(flags: ["my-flag"])
        )
        let timedOut = expectation("SDK timed out")
        let listener = TestEventListener(timeoutExpectation: timedOut)
        factory = try buildFactory(httpClient: httpMock, readyTimeout: 1)
        factory.client.addEventListener(listener)
        waitFor(timedOut, timeout: 5)
    }
}
