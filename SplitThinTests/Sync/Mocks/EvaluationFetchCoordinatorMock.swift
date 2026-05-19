import Foundation
@testable import SplitThin

final class EvaluationFetchCoordinatorMock: EvaluationFetchCoordinator, @unchecked Sendable {

    var fetchCalls: [(target: Target, filters: EvaluationFilters?, reason: FetchReason)] = []
    var refetchAllCalls: [RefetchDelay] = []
    var refetchKeysCalls: [(matchingKeys: Set<String>, delay: RefetchDelay)] = []
    var unregisterCalls: [Target] = []
    var evaluationsToReturn: [EvaluationResult] = []
    var changeNumberToReturn: Int64? = nil
    var errorToThrow: Error?
    var onFetchCallback: (() -> Void)?
    var onRefetchAllCallback: (() -> Void)?
    var registeredMatchingKeys: [String] = []

    private let lock = NSLock()

    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult {
        withLock(lock) { fetchCalls.append((target, filters, reason)) }
        onFetchCallback?()
        if let error = errorToThrow { throw error }
        return FetchResult(evaluations: evaluationsToReturn, changeNumber: changeNumberToReturn)
    }

    func refetchAll(delay: RefetchDelay) async {
        withLock(lock) { refetchAllCalls.append(delay) }
        onRefetchAllCallback?()
    }

    func refetchKeys(_ matchingKeys: Set<String>, delay: RefetchDelay) async {
        withLock(lock) { refetchKeysCalls.append((matchingKeys, delay)) }
        onRefetchAllCallback?()
    }

    func unregister(target: Target) {
        withLock(lock) { unregisterCalls.append(target) }
    }
}
