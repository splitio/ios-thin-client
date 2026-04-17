import Foundation
import Http
@testable import SplitThin

final class SecureHttpClientMock: SecureHttpClient, @unchecked Sendable {

    var fetchEvaluationsResult: HttpResponse?
    var fetchEvaluationsResultByKey = [String: Result<HttpResponse, Error>]()
    var postEventsResult: HttpResponse?
    var postTelemetryResult: HttpResponse?
    var errorToThrow: Error?
    var fetchDelay: UInt64 = 0

    var fetchEvaluationsCalls: [(target: Target, filters: EvaluationFilters?)] = []
    var fetchEvaluationsCallTimestamps: [Date] = []
    var postEventsCalls: [Data] = []
    var postTelemetryCalls: [Data] = []
    private let lock = NSLock()

    func fetchEvaluations(target: Target, filters: EvaluationFilters?) async throws -> HttpResponse {
        withLock(lock) {
            fetchEvaluationsCalls.append((target, filters))
            fetchEvaluationsCallTimestamps.append(Date())
        }

        if fetchDelay > 0 {
            try? await Task.sleep(nanoseconds: fetchDelay)
        }

        if let perKeyResult = fetchEvaluationsResultByKey[target.matchingKey] {
            switch perKeyResult {
                case .success(let response): return response
                case .failure(let error): throw error
            }
        }

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

    func reset() {
        withLock(lock) {
            fetchEvaluationsResult = nil
            postEventsResult = nil
            postTelemetryResult = nil
            errorToThrow = nil
            fetchDelay = 0
            fetchEvaluationsCalls = []
            fetchEvaluationsCallTimestamps = []
            postEventsCalls = []
            postTelemetryCalls = []
        }
    }
}
