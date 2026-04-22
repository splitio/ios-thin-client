import XCTest
import Http
import BackoffCounter
@testable import SplitThin

final class RetryableHttpClientEventsTest: XCTestCase {

    private var httpClientMock: HttpClientStub!
    private var backoffCounterMock: BackoffCounterStub!
    private var observerSpy: ObserverSpy!

    override func setUp() {
        super.setUp()
        httpClientMock = HttpClientStub()
        backoffCounterMock = BackoffCounterStub()
        observerSpy = ObserverSpy()
    }

    override func tearDown() {
        httpClientMock = nil
        backoffCounterMock = nil
        observerSpy = nil
        super.tearDown()
    }

    func testSuccessEmitsStartAndSucceeded() async throws {
        httpClientMock.responses = [HttpResponse(code: 200, data: Data())]

        let client = createClient()
        _ = try await client.execute(createEndpoint(), category: .evaluations)

        XCTAssertEqual(observerSpy.eventNames, ["httpRequestStarted", "httpRequestSucceeded"])
    }

    func testNonRetryableFailureEmitsStartAndNonRetryable() async throws {
        httpClientMock.responses = [HttpResponse(code: 404, data: nil)]

        let client = createClient()
        _ = try await client.execute(createEndpoint(), category: .evaluations)

        XCTAssertEqual(observerSpy.eventNames, ["httpRequestStarted", "httpRequestFailedNonRetryable"])
    }

    func testRetryExhaustedEmitsRetryableAndExhausted() async throws {
        httpClientMock.responses = Array(repeating: HttpResponse(code: 500, data: nil), count: 4)

        let client = createClient()
        _ = try? await client.execute(createEndpoint(), category: .evaluations)

        let names = observerSpy.eventNames
        XCTAssertEqual(names.first, "httpRequestStarted")
        XCTAssertTrue(names.contains("httpRequestFailedRetryable"))
        XCTAssertEqual(names.last, "httpRetryExhausted")
    }

    func testRetryThenSuccessEmitsRetryableAndSucceeded() async throws {
        httpClientMock.responses = [
            HttpResponse(code: 500, data: nil),
            HttpResponse(code: 200, data: Data())
        ]

        let client = createClient()
        _ = try await client.execute(createEndpoint(), category: .evaluations)

        let names = observerSpy.eventNames
        XCTAssertEqual(names.first, "httpRequestStarted")
        XCTAssertTrue(names.contains("httpRequestFailedRetryable"))
        XCTAssertEqual(names.last, "httpRequestSucceeded")
    }

    // MARK: - Helpers

    private func createClient() -> DefaultRetryableHttpClient {
        DefaultRetryableHttpClient(
            httpClient: httpClientMock,
            observer: observerSpy,
            backoffCounterFactory: { [backoffCounterMock] _ in backoffCounterMock! }
        )
    }

    private func createEndpoint() -> Endpoint {
        Endpoint.builder(baseUrl: URL(string: "https://api.example.com")!, path: "test")
                .set(method: .get)
                .build()
    }
}
