import XCTest
import Http
@testable import SplitThin

final class EvaluationResultE2ETest: XCTestCase {

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

    func testEvaluationResultExposesChangeNumberFromServerResponse() async throws {
        let till: Int64 = 99999
        httpMock.fetchEvaluationsResult = HttpResponse(
            code: 200,
            data: mockEvaluationsData(flags: ["my-flag"], till: till)
        )
        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        let result = factory.client.getTreatment("my-flag")
        XCTAssertEqual(result.changeNumber, till)
    }
}
