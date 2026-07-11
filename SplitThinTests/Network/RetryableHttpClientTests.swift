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
            try await client.execute(endpoint, category: .evaluations)
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

        try await client.execute(endpoint, category: .evaluations)

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

    // MARK: - URLRequest path

    func testExecuteRequestReturnsResponseFromSender() async throws {
        let sentRequests = SentRequestsBox()
        let client = createClient(urlRequestSender: { request in
            sentRequests.append(request)
            return HttpResponse(code: 200, data: Data("ok".utf8))
        })

        let request = URLRequest(url: URL(string: "https://auth.example.com/api/v3/auth?key=a%2Cb")!)
        let response = try await client.execute(request: request, category: .auth)

        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(sentRequests.all.count, 1)
        XCTAssertEqual(sentRequests.all[0].url?.absoluteString, "https://auth.example.com/api/v3/auth?key=a%2Cb")
    }

    func testExecuteRequestRetriesOnRetryableStatus() async throws {
        let responses = ResponseQueueBox([
            HttpResponse(code: 500, data: nil),
            HttpResponse(code: 200, data: Data())
        ])
        let client = createClient(urlRequestSender: { _ in responses.next() })

        let request = URLRequest(url: URL(string: "https://auth.example.com/api/v3/auth")!)
        let response = try await client.execute(request: request, category: .auth)

        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(responses.consumed, 2)
    }

    // MARK: - Helpers

    private func createClient(policies: RetryPoliciesByCategory? = nil, urlRequestSender: DefaultRetryableHttpClient.UrlRequestSender? = nil) -> DefaultRetryableHttpClient {
        DefaultRetryableHttpClient(
            httpClient: httpClientMock,
            observer: ObserverSpy(),
            policies: policies,
            backoffCounterFactory: { [backoffCounterMock] _ in backoffCounterMock! },
            urlRequestSender: urlRequestSender
        )
    }

    private func createEndpoint() -> Endpoint {
        Endpoint.builder(baseUrl: URL(string: "https://api.example.com")!, path: "test")
            .set(method: .get)
            .build()
    }
}

// Thread-safe helpers so the @Sendable urlRequestSender closure can record/return values.
private final class SentRequestsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
    }

    var all: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }
}

private final class ResponseQueueBox: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [HttpResponse]
    private(set) var consumed = 0

    init(_ responses: [HttpResponse]) {
        self.responses = responses
    }

    func next() -> HttpResponse {
        lock.lock(); defer { lock.unlock() }
        guard consumed < responses.count else { return HttpResponse(code: 200, data: nil) }
        let response = responses[consumed]
        consumed += 1
        return response
    }
}
