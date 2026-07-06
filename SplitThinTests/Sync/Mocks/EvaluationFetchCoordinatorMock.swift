import Foundation
@testable import SplitThin

final class EvaluationFetchCoordinatorMock: EvaluationFetchCoordinator, @unchecked Sendable {

    var fetchCalls: [(target: Target, filters: EvaluationFilters?, reason: FetchReason)] = []
    var refetchAllCalls: [RefetchDelay] = []
    var refetchKeysCalls: [(matchingKeys: Set<String>, delay: RefetchDelay)] = []
    var unregisterCalls: [Target] = []
    var evaluationsToReturn: [EvaluationResult] = []
    var changeNumberToReturn: Int64? = nil
    var shouldApplyToCacheToReturn = true
    var errorToThrow: Error?
    var onFetchCallback: (() -> Void)?
    var onRefetchAllCallback: (() -> Void)?
    var onRefetchKeysCallback: (() -> Void)?
    var registeredMatchingKeys: [String] = []
    var registerOnUpdateActionCalls: [Key] = []
    var unregisterOnUpdateActionCalls: [Key] = []
    var onUpdateActions: [Key: (FetchResult) -> Void] = [:]

    private let lock = NSLock()

    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult {
        withLock(lock) { fetchCalls.append((target, filters, reason)) }
        onFetchCallback?()
        if let error = errorToThrow { throw error }
        return FetchResult(evaluations: evaluationsToReturn, changeNumber: changeNumberToReturn, shouldApplyToCache: shouldApplyToCacheToReturn)
    }

    func refetchAll(delay: RefetchDelay) async {
        withLock(lock) { refetchAllCalls.append(delay) }
        onRefetchAllCallback?()
    }

    func refetchKeys(_ matchingKeys: Set<String>, delay: RefetchDelay) async {
        withLock(lock) { refetchKeysCalls.append((matchingKeys, delay)) }
        onRefetchKeysCallback?()
    }

    func registerOnUpdateAction(for key: Key, action: @escaping (FetchResult) -> Void) {
        withLock(lock) {
            registerOnUpdateActionCalls.append(key)
            onUpdateActions[key] = action
        }
    }

    func unregisterOnUpdateAction(for key: Key) {
        withLock(lock) {
            unregisterOnUpdateActionCalls.append(key)
            onUpdateActions.removeValue(forKey: key)
        }
    }

    func unregister(target: Target) {
        withLock(lock) {
            unregisterCalls.append(target)
        }
    }
}
