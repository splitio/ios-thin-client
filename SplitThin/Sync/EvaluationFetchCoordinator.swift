import Foundation
import Logging

enum FetchReason: Sendable {
    case initialization
    case targetSwitch
    case periodic
    case push
}

enum EvaluationFetchError: Error {
    case fetchFailed
}

private struct FetchKey: Hashable {
    let target: Target
    let filters: EvaluationFilters?
}

protocol EvaluationFetchCoordinator: Sendable {
    /// Coordinates fetch requests so only one relevant fetch runs at a time.
    /// Returns the fetched evaluations on success (may be empty), or nil on failure.
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async -> [EvaluationResult]?

    /// Re-fetches all previously fetched keys with push reason.
    func refetchAll(notification: EvaluationUpdateNotification?) async
}

final class DefaultEvaluationFetchCoordinator: EvaluationFetchCoordinator, @unchecked Sendable {

    private let provider: EvaluationProvider
    private let storage: EvaluationWriteStorage
    private let delayProvider: DelayProvider

    // Called after a successful push fetch, with the target and updated flag names.
    var onEvaluationsUpdated: ((Target, [String]) -> Void)?

    private var inFlightTasks = [FetchKey: Task<[EvaluationResult]?, Never>]()
    private var fetchedKeys = Set<FetchKey>()
    private let lock = NSLock()

    init(provider: EvaluationProvider, storage: EvaluationWriteStorage,
         delayProvider: @escaping DelayProvider = buildDelayProvider()) {
        self.provider = provider
        self.storage = storage
        self.delayProvider = delayProvider
    }

    @discardableResult
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async -> [EvaluationResult]? {
        let key = FetchKey(target: target, filters: filters)

        let existingTask: Task<[EvaluationResult]?, Never>? = withLock(lock) {
            fetchedKeys.insert(key)
            return inFlightTasks[key]
        }

        if let task = existingTask {
            Logger.d("EvaluationFetchCoordinator: Awaiting in-flight fetch for \(target.matchingKey) (reason: \(reason))")
            return await task.value
        }

        let task = Task<[EvaluationResult]?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.performFetch(target: target, filters: filters, reason: reason)
        }

        withLock(lock) { inFlightTasks[key] = task }
        let result = await task.value
        withLock(lock) { inFlightTasks.removeValue(forKey: key) }

        return result
    }

    func refetchAll(notification: EvaluationUpdateNotification?) async {
        let keys = withLock(lock) { fetchedKeys }
        for key in keys {
            let delay = delayProvider(notification, key.target.matchingKey)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            await fetchIfNeeded(target: key.target, filters: key.filters, reason: .push)
        }
    }

    private func performFetch(target: Target, filters: EvaluationFilters?, reason: FetchReason) async -> [EvaluationResult]? {
        guard let result = await provider.fetch(target: target, filters: filters) else {
            Logger.d("EvaluationFetchCoordinator: Fetch failed for \(target.matchingKey) (reason: \(reason))")
            return nil
        }

        if reason == .push {
            let change = EvaluationChange(
                target: target,
                changeNumber: result.till ?? -1,
                evaluations: result.evaluations
            )
            try? await storage.upsert(change: change)
            let flagNames = result.evaluations.map { $0.flag }
            onEvaluationsUpdated?(target, flagNames)
        }
        Logger.d("EvaluationFetchCoordinator: Fetched \(result.evaluations.count) evaluations for \(target.matchingKey) (reason: \(reason))")
        return result.evaluations
    }
}
