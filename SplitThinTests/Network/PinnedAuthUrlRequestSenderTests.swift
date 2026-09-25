import XCTest
import Http
@testable import SplitThin

final class PinnedAuthUrlRequestSenderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    func testPinnedSenderMapsHttpResponseWithoutHittingTheNetwork() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.body = Data("auth-ok".utf8)

        let (sender, session) = DefaultSplitFactoryBuilder.makePinnedAuthUrlRequestSender(sessionConfiguration: stubbedSessionConfiguration())
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://auth.split.io/api/auth")!)

        let response = try await sender(request)

        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(response.data, Data("auth-ok".utf8))
        XCTAssertEqual(StubURLProtocol.lastRequest?.url, request.url)
    }

    func testPinnedSenderMapsTransportErrorToRetryableNetworkError() async throws {
        StubURLProtocol.error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)

        let (sender, session) = DefaultSplitFactoryBuilder.makePinnedAuthUrlRequestSender(sessionConfiguration: stubbedSessionConfiguration())
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://auth.split.io/api/auth")!)

        do {
            _ = try await sender(request)
            XCTFail("Expected RetryableHttpError.networkError")
        } catch let error as RetryableHttpError {
            if case .networkError = error {} else {
                XCTFail("Expected .networkError, got \(error)")
            }
        }
    }

    func testRetryableClientRetriesThroughPinnedSender() async throws {
        StubURLProtocol.statusCodes = [500, 200]
        StubURLProtocol.body = Data()

        let (sender, session) = DefaultSplitFactoryBuilder.makePinnedAuthUrlRequestSender(sessionConfiguration: stubbedSessionConfiguration())
        defer { session.invalidateAndCancel() }

        let backoff = BackoffCounterStub()
        let client = DefaultRetryableHttpClient(httpClient: HttpClientStub(), observer: ObserverSpy(), backoffCounterFactory: { _ in backoff }, urlRequestSender: sender)

        let response = try await client.execute(request: URLRequest(url: URL(string: "https://auth.split.io/api/auth")!), category: .auth)

        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(StubURLProtocol.handledCount, 2)
        XCTAssertEqual(backoff.getNextRetryTimeCallCount, 1)
    }

    private func stubbedSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    // Shared stub state; guarded by `lock` when read from URLSession callbacks.
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var statusCodes: [Int]?
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var error: Error?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var handledCount = 0

    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        statusCode = 200
        statusCodes = nil
        body = Data()
        error = nil
        lastRequest = nil
        handledCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.lastRequest = request
        Self.handledCount += 1
        let error = Self.error
        let code: Int
        if let codes = Self.statusCodes, !codes.isEmpty {
            let index = min(Self.handledCount - 1, codes.count - 1)
            code = codes[index]
        } else {
            code = Self.statusCode
        }
        let body = Self.body
        Self.lock.unlock()

        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
