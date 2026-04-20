import Foundation
@testable import SplitThin

final class EvaluationFetchCoordinatorMock: EvaluationFetchCoordinator, @unchecked Sendable {

    var fetchCalls: [(target: Target, filters: EvaluationFilters?, reason: FetchReason)] = []
    var evaluationsToReturn: [EvaluationResult] = []
    var changeNumberToReturn: Int64? = nil
    var errorToThrow: Error?

    private let lock = NSLock()

    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult {
        withLock(lock) { fetchCalls.append((target, filters, reason)) }
        if let error = errorToThrow {
            throw error
        }
        return FetchResult(evaluations: evaluationsToReturn, changeNumber: changeNumberToReturn)
    }
}
