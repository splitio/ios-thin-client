import Foundation
@testable import SplitThin

final class EvaluationFetchCoordinatorMock: EvaluationFetchCoordinator, @unchecked Sendable {

    var fetchCalls: [(target: Target, filters: EvaluationFilters?, reason: FetchReason)] = []
    var evaluationsToReturn: [EvaluationResult] = []
    var errorToThrow: Error?

    private let lock = NSLock()

    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> [EvaluationResult] {
        withLock(lock) { fetchCalls.append((target, filters, reason)) }
        if let error = errorToThrow {
            throw error
        }
        return evaluationsToReturn
    }
}
