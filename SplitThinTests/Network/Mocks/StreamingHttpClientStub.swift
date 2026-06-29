import Foundation
import Http
@testable import SplitThin

final class StreamingHttpClientStub: HttpClient, @unchecked Sendable {

    let streamRequest = FakeHttpStreamRequest()

    private let lock = NSLock()
    private var _sendStreamRequestCount = 0
    var sendStreamRequestCount: Int {
        withLock(lock) { _sendStreamRequestCount }
    }

    func sendRequest(endpoint: Endpoint, parameters: HttpParameters?, headers: [String: String]?, body: Data?) throws -> HttpDataRequest {
        HttpDataRequestStub(response: HttpResponse(code: 200, data: nil))
    }

    func sendStreamRequest(endpoint: Endpoint, parameters: HttpParameters?, headers: [String: String]?) throws -> HttpStreamRequest {
        withLock(lock) {_sendStreamRequestCount += 1 }
        return streamRequest
    }
}

final class FakeHttpStreamRequest: HttpStreamRequest, @unchecked Sendable {

    private let lock = NSLock()
    private var _closeCallCount = 0
    var closeCallCount: Int {
        withLock(lock) { _closeCallCount }
    }

    private var responseHandler: ResponseHandler?
    private var incomingDataHandler: IncomingDataHandler?
    private var closeHandler: CloseHandler?
    private var errorHandler: ErrorHandler?

    // MARK: HttpRequest
    var identifier: Int { 0 }
    var url: URL { URL(string: "https://fake.endpoint/sse")! }
    var method: HttpMethod { .get }
    var parameters: HttpParameters? { nil }
    var headers: HttpHeaders { [:] }
    var body: Data? { nil }
    var responseCode: Int { 200 }
    var pinnedCredentialFail: Bool { false }

    func send() {}
    func setResponse(code: Int) {}
    func notifyIncomingData(_ data: Data) { incomingDataHandler?(data) }
    func complete(error: HttpError?) {}
    func notifyPinnedCredentialFail() {}

    // MARK: HttpStreamRequest
    func getResponse(responseHandler: @escaping ResponseHandler, incomingDataHandler: @escaping IncomingDataHandler, closeHandler: @escaping CloseHandler, errorHandler: @escaping ErrorHandler) -> Self {
        self.responseHandler = responseHandler
        self.incomingDataHandler = incomingDataHandler
        self.closeHandler = closeHandler
        self.errorHandler = errorHandler
        return self
    }

    func simulateConnected() { 
        responseHandler?(HttpResponse(code: 200)) 
    }

    func close() {
        withLock(lock) { _closeCallCount += 1 }
    }
}
