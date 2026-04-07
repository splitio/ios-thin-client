import Foundation
import Logging

public enum FetchReason: Sendable {
    case initialization
    case targetSwitch
    case periodic
    case push
}

private struct FetchKey: Hashable {
    let target: Target
    let filters: EvaluationFilters?
}

protocol EvaluationFetchCoordinator: Sendable {
    /// Coordinates fetch requests so only one relevant fetch runs at a time.
    /// Returns the fetched evaluations, or empty array if deduplicated/failed.
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async -> [EvaluationResult]
}

final class DefaultEvaluationFetchCoordinator: EvaluationFetchCoordinator, @unchecked Sendable {

    private let provider: EvaluationProvider
    private let storage: EvaluationWriteStorage?

    private var inFlightTasks = [FetchKey: Task<[EvaluationResult], Never>]()
    private let lock = NSLock()

    init(provider: EvaluationProvider, storage: EvaluationWriteStorage? = nil) {
        self.provider = provider
        self.storage = storage
    }

    @discardableResult
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async -> [EvaluationResult] {
        let key = FetchKey(target: target, filters: filters)

        let existingTask: Task<[EvaluationResult], Never>? = withLock(lock) { inFlightTasks[key] }

        if let task = existingTask {
            Logger.d("EvaluationFetchCoordinator: Awaiting in-flight fetch for \(target.matchingKey) (reason: \(reason))")
            return await task.value
        }

        let task = Task<[EvaluationResult], Never> { [weak self] in
            guard let self else { return [] }
            return await self.performFetch(target: target, filters: filters, reason: reason)
        }

        withLock(lock) { inFlightTasks[key] = task }
        let result = await task.value
        withLock(lock) { inFlightTasks.removeValue(forKey: key) }

        return result
    }

    private func performFetch(target: Target, filters: EvaluationFilters?, reason: FetchReason) async -> [EvaluationResult] {
        if let result = await provider.fetch(target: target, filters: filters) {
            if let storage {
                let change = EvaluationChange(
                    target: target,
                    changeNumber: result.till ?? -1,
                    evaluations: result.evaluations
                )
                try? await storage.upsert(change: change)
            }
            Logger.d("EvaluationFetchCoordinator: Fetched \(result.evaluations.count) evaluations for \(target.matchingKey) (reason: \(reason))")
            return result.evaluations
        }

        Logger.d("EvaluationFetchCoordinator: Fetch failed for \(target.matchingKey) (reason: \(reason))")
        return []
    }
}
