import Foundation
@testable import SplitThin

final class EvaluationFetchCoordinatorMock: EvaluationFetchCoordinator, @unchecked Sendable {

    var fetchCalls: [(target: Target, filters: EvaluationFilters?, reason: FetchReason)] = []
    var refetchAllCalls: [EvaluationUpdateNotification?] = []
    var evaluationsToReturn: [EvaluationResult] = []
    var changeNumberToReturn: Int64? = nil
    var errorToThrow: Error?
    var onFetchCallback: (() -> Void)?
    var onRefetchAllCallback: (() -> Void)?

    private let lock = NSLock()

    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult {
        withLock(lock) { fetchCalls.append((target, filters, reason)) }
        onFetchCallback?()
        if let error = errorToThrow {
            throw error
        }
        return FetchResult(evaluations: evaluationsToReturn, changeNumber: changeNumberToReturn)
    }

    func refetchAll(notification: EvaluationUpdateNotification?) async {
        withLock(lock) { refetchAllCalls.append(notification) }
        onRefetchAllCallback?()
    }
}
