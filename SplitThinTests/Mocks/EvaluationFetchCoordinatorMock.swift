import Foundation
@testable import SplitThin

final class EvaluationFetchCoordinatorMock: EvaluationFetchCoordinator, @unchecked Sendable {

    var fetchCalls: [(target: Target, filters: EvaluationFilters?, reason: FetchReason)] = []
    var hasInFlightCalls: [Target] = []
    var awaitCalls: [Target] = []
    var evaluationsToReturn: [EvaluationResult] = []
    var hasInFlightResult: Bool = false

    private let lock = NSLock()

    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async -> [EvaluationResult] {
        withLock(lock) { fetchCalls.append((target, filters, reason)) }
        return evaluationsToReturn
    }

    func hasInFlightFetch(for target: Target) -> Bool {
        withLock(lock) { hasInFlightCalls.append(target) }
        return hasInFlightResult
    }

    func awaitInFlightFetch(for target: Target) async -> [EvaluationResult] {
        withLock(lock) { awaitCalls.append(target) }
        return evaluationsToReturn
    }
}
