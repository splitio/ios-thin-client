import Foundation
import Http
@testable import SplitThin

final class RetryableHttpClientMock: RetryableHttpClient, @unchecked Sendable {

    var responses: [HttpResponse] = []
    var errorToThrow: Error?
    var executeCalls: [(endpoint: Endpoint, category: RequestCategory, body: Data?)] = []
    var requestCalls: [(request: URLRequest, category: RequestCategory)] = []
    var delaySeconds: TimeInterval = 0

    private var responseIndex = 0
    private let lock = NSLock()

    func execute(_ endpoint: Endpoint, category: RequestCategory, body: Data?) async throws -> HttpResponse {
        withLock(lock) {
            executeCalls.append((endpoint, category, body))
        }
        return try await respond()
    }

    func execute(request: URLRequest, category: RequestCategory) async throws -> HttpResponse {
        withLock(lock) {
            requestCalls.append((request, category))
        }
        return try await respond()
    }

    private func respond() async throws -> HttpResponse {
        if delaySeconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        }

        if let error = errorToThrow {
            throw error
        }

        return withLock(lock) {
            guard responseIndex < responses.count else {
                return HttpResponse(code: 200, data: nil)
            }

            let response = responses[responseIndex]
            responseIndex += 1
            return response
        }
    }

    func reset() {
        withLock(lock) {
            responses = []
            errorToThrow = nil
            executeCalls = []
            requestCalls = []
            responseIndex = 0
            delaySeconds = 0
        }
    }
}
