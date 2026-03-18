import Foundation
import Http
@testable import SplitThin

final class SecureHttpClientMock: SecureHttpClient, @unchecked Sendable {

    var fetchEvaluationsResult: HttpResponse?
    var postEventsResult: HttpResponse?
    var postTelemetryResult: HttpResponse?
    var errorToThrow: Error?

    var fetchEvaluationsCalls: [(target: Target, filters: EvaluationFilters?)] = []
    var postEventsCalls: [Data] = []
    var postTelemetryCalls: [Data] = []
    var openStreamingCalls: [String] = []
    var closeStreamingCallCount = 0

    private let lock = NSLock()

    func fetchEvaluations(target: Target, filters: EvaluationFilters?) async throws -> HttpResponse {
        withLock(lock) { fetchEvaluationsCalls.append((target, filters)) }

        if let error = errorToThrow {
            throw error
        }
        return fetchEvaluationsResult ?? HttpResponse(code: 200, data: nil)
    }

    func postEvents(payload: Data) async throws -> HttpResponse {
        withLock(lock) { postEventsCalls.append(payload) }

        if let error = errorToThrow {
            throw error
        }
        return postEventsResult ?? HttpResponse(code: 200, data: nil)
    }

    func postTelemetry(payload: Data) async throws -> HttpResponse {
        withLock(lock) { postTelemetryCalls.append(payload) }

        if let error = errorToThrow {
            throw error
        }
        return postTelemetryResult ?? HttpResponse(code: 200, data: nil)
    }

    func openStreaming(token: String) async throws {
        withLock(lock) { openStreamingCalls.append(token) }

        if let error = errorToThrow {
            throw error
        }
    }

    func closeStreaming() async {
        withLock(lock) { closeStreamingCallCount += 1 }
    }

    func reset() {
        withLock(lock) {
            fetchEvaluationsResult = nil
            postEventsResult = nil
            postTelemetryResult = nil
            errorToThrow = nil
            fetchEvaluationsCalls = []
            postEventsCalls = []
            postTelemetryCalls = []
            openStreamingCalls = []
            closeStreamingCallCount = 0
        }
    }
}
