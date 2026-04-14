import XCTest
import Http
import BackoffCounter
@testable import SplitThin

final class DefaultRetryableHttpClientTest: XCTestCase {

    private var httpClientMock: HttpClientStub!
    private var backoffCounterMock: BackoffCounterStub!

    override func setUp() {
        super.setUp()
        httpClientMock = HttpClientStub()
        backoffCounterMock = BackoffCounterStub()
    }

    func testSuccessfulRequestReturnsImmediately() async throws {
        httpClientMock.responses = [HttpResponse(code: 200, data: Data())]

        let client = createClient()
        let endpoint = createEndpoint()

        let response = try await client.execute(endpoint, category: .evaluations)

        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(httpClientMock.requestCount, 1)
    }

    func testRetriesOnFailureWithDefaultPolicy() async throws {
        httpClientMock.responses = [
            HttpResponse(code: 500, data: nil),
            HttpResponse(code: 500, data: nil),
            HttpResponse(code: 200, data: Data())
        ]

        let client = createClient()
        let endpoint = createEndpoint()

        let response = try await client.execute(endpoint, category: .evaluations)

        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(httpClientMock.requestCount, 3)
        XCTAssertEqual(backoffCounterMock.getNextRetryTimeCallCount, 2)
    }

    func testThrowsWhenMaxAttemptsReached() async throws {
        httpClientMock.responses = [
            HttpResponse(code: 500, data: nil),
            HttpResponse(code: 500, data: nil),
            HttpResponse(code: 500, data: nil),
            HttpResponse(code: 500, data: nil)
        ]

        let client = createClient()
        let endpoint = createEndpoint()

        do {
            _ = try await client.execute(endpoint, category: .evaluations)
            XCTFail("Expected maxAttemptsReached error")
        } catch let error as RetryableHttpError {
            if case .maxAttemptsReached(let statusCode, let attempts) = error {
                XCTAssertEqual(statusCode, 500)
                XCTAssertEqual(attempts, 3)
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testNoRetryFor404() async throws {
        httpClientMock.responses = [
            HttpResponse(code: 404, data: nil)
        ]

        let client = createClient()
        let endpoint = createEndpoint()

        let response = try await client.execute(endpoint, category: .evaluations)

        XCTAssertEqual(response.code, 404)
        XCTAssertEqual(httpClientMock.requestCount, 1)
    }

    func testNoRetryFor400() async throws {
        httpClientMock.responses = [
            HttpResponse(code: 400, data: nil)
        ]

        let client = createClient()
        let endpoint = createEndpoint()

        let response = try await client.execute(endpoint, category: .evaluations)

        XCTAssertEqual(response.code, 400)
        XCTAssertEqual(httpClientMock.requestCount, 1)
    }

    func testNoRetryFor401() async throws {
        httpClientMock.responses = [
            HttpResponse(code: 401, data: nil)
        ]

        let client = createClient()
        let endpoint = createEndpoint()

        let response = try await client.execute(endpoint, category: .evaluations)

        XCTAssertEqual(response.code, 401)
        XCTAssertEqual(httpClientMock.requestCount, 1)
    }

    func testResetsBackoffCounterOnNewRequest() async throws {
        httpClientMock.responses = [HttpResponse(code: 200, data: Data())]

        let client = createClient()
        let endpoint = createEndpoint()

        _ = try await client.execute(endpoint, category: .evaluations)

        XCTAssertEqual(backoffCounterMock.resetCounterCallCount, 1)
    }

    func testCancellationStopsRetryLoop() async throws {
        httpClientMock.responses = Array(repeating: HttpResponse(code: 500, data: nil), count: 100)
        backoffCounterMock.retryTime = 10.0

        let policies: RetryPoliciesByCategory = [
            .evaluations: CategoryRetryPolicies(
                fallback: RetryPolicy(maxAttempts: -1, backoffBaseSeconds: 1)
            )
        ]

        let client = createClient(policies: policies)
        let endpoint = createEndpoint()

        let task = Task {
            try await client.execute(endpoint, category: .evaluations)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation error")
        } catch is CancellationError {
            XCTAssertLessThan(httpClientMock.requestCount, 100)
        }
    }

    func testPassesBodyToRequest() async throws {
        httpClientMock.responses = [HttpResponse(code: 200, data: Data())]
        let bodyData = "test body".data(using: .utf8)!

        let client = createClient()
        let endpoint = createEndpoint()

        _ = try await client.execute(endpoint, category: .events, body: bodyData)

        XCTAssertEqual(httpClientMock.lastBody, bodyData)
    }

    // MARK: - Helpers

    private func createClient(policies: RetryPoliciesByCategory? = nil) -> DefaultRetryableHttpClient {
        DefaultRetryableHttpClient(
            httpClient: httpClientMock,
            policies: policies,
            backoffCounterFactory: { [backoffCounterMock] _ in backoffCounterMock! }
        )
    }

    private func createEndpoint() -> Endpoint {
        Endpoint.builder(baseUrl: URL(string: "https://api.example.com")!, path: "test")
            .set(method: .get)
            .build()
    }
}

// MARK: - Test Doubles

private final class HttpClientStub: HttpClient, @unchecked Sendable {
    var responses: [HttpResponse] = []
    var requestCount = 0
    var lastBody: Data?
    private let lock = NSLock()

    func sendRequest(endpoint: Endpoint, parameters: HttpParameters?, headers: [String: String]?, body: Data?) throws -> HttpDataRequest {
        lock.lock()
        let index = requestCount
        requestCount += 1
        lastBody = body
        lock.unlock()

        let response = index < responses.count ? responses[index] : HttpResponse(code: 200, data: nil)
        return HttpDataRequestStub(response: response)
    }

    func sendStreamRequest(endpoint: Endpoint, parameters: HttpParameters?, headers: [String: String]?) throws -> HttpStreamRequest {
        fatalError("Not implemented")
    }
}

private final class HttpDataRequestStub: HttpDataRequest, @unchecked Sendable {
    let response: HttpResponse

    init(response: HttpResponse) {
        self.response = response
    }

    var identifier: Int { 0 }
    var url: URL { URL(string: "https://example.com")! }
    var method: HttpMethod { .get }
    var parameters: HttpParameters? { nil }
    var headers: HttpHeaders { [:] }
    var body: Data? { nil }
    var responseCode: Int { response.code }
    var pinnedCredentialFail: Bool { false }
    var data: Data? { response.data }

    func send() {}
    func setResponse(code: Int) {}
    func notifyIncomingData(_ data: Data) {}
    func complete(error: HttpError?) {}
    func notifyPinnedCredentialFail() {}

    @discardableResult
    func getResponse(completionHandler: @escaping RequestCompletionHandler, errorHandler: @escaping RequestErrorHandler) -> Self {
        DispatchQueue.global().async {
            completionHandler(self.response)
        }
        return self
    }
}

private final class BackoffCounterStub: BackoffCounter, @unchecked Sendable {
    var retryTime: Double = 0.001
    var getNextRetryTimeCallCount = 0
    var resetCounterCallCount = 0
    private let lock = NSLock()

    func getNextRetryTime() -> Double {
        lock.lock()
        defer { lock.unlock() }
        getNextRetryTimeCallCount += 1
        return retryTime
    }

    func resetCounter() {
        lock.lock()
        defer { lock.unlock() }
        resetCounterCallCount += 1
    }
}
