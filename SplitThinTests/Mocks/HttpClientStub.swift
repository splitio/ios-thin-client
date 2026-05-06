import Foundation
import Http
import BackoffCounter
@testable import SplitThin

final class HttpClientStub: HttpClient, @unchecked Sendable {
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

final class HttpDataRequestStub: HttpDataRequest, @unchecked Sendable {
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

final class BackoffCounterStub: BackoffCounter, @unchecked Sendable {
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
