import Foundation
@testable import SplitThin

final class EvaluationFetchCoordinatorMock: EvaluationFetchCoordinator, @unchecked Sendable {

    var fetchCalls: [(target: Target, filters: EvaluationFilters?, reason: FetchReason)] = []
    var refetchAllCalls: [EvaluationUpdateNotification?] = []
    var evaluationsToReturn: [EvaluationResult]? = []
    var onFetchCallback: (() -> Void)?
    var onRefetchAllCallback: (() -> Void)?

    private let lock = NSLock()

    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async -> [EvaluationResult]? {
        withLock(lock) { fetchCalls.append((target, filters, reason)) }
        onFetchCallback?()
        return evaluationsToReturn
    }

    func refetchAll(notification: EvaluationUpdateNotification?) async {
        withLock(lock) { refetchAllCalls.append(notification) }
        onRefetchAllCallback?()
    }
}
