import Foundation
@testable import SplitThin

final class EvaluationProviderMock: EvaluationProvider, @unchecked Sendable {

    var resultToReturn: EvaluationsResult?
    var errorToThrow: Error?
    var fetchCalls: [(target: Target, filters: EvaluationFilters?)] = []
    var fetchDelay: UInt64 = 0

    private let lock = NSLock()

    func fetch(target: Target, filters: EvaluationFilters?) async throws -> EvaluationsResult? {
        withLock(lock) { fetchCalls.append((target, filters)) }

        if fetchDelay > 0 {
            try? await Task.sleep(nanoseconds: fetchDelay)
        }

        if let error = errorToThrow {
            throw error
        }

        return resultToReturn
    }
}
