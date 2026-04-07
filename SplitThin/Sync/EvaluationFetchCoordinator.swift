import Foundation
import Logging

public enum FetchReason: Sendable {
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

public protocol EvaluationFetchCoordinator: Sendable {
    /// Coordinates fetch requests so only one relevant fetch runs at a time.
    /// Returns the fetched evaluations (can be empty on success). Throws on failure.
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> [EvaluationResult]
}

final class DefaultEvaluationFetchCoordinator: EvaluationFetchCoordinator, @unchecked Sendable {

    private let provider: EvaluationProvider
    private let storage: EvaluationWriteStorage?

    private var inFlightTasks = [FetchKey: Task<[EvaluationResult], Error>]()
    private let lock = NSLock()

    init(provider: EvaluationProvider, storage: EvaluationWriteStorage? = nil) {
        self.provider = provider
        self.storage = storage
    }

    @discardableResult
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> [EvaluationResult] {
        let key = FetchKey(target: target, filters: filters)

        // Atomic tasks
        let task: Task<[EvaluationResult], Error> = withLock(lock) {

            // 1. Check for deduplications
            if let existing = inFlightTasks[key] {
                Logger.d("EvaluationFetchCoordinator: Awaiting in-flight fetch for \(target.matchingKey) (reason: \(reason))")
                return existing
            }

            // 2. Create request and add to the list (for deduplication)
            let newTask = Task<[EvaluationResult], Error> { [weak self] in
                guard let self else { throw EvaluationFetchError.fetchFailed }
                defer { withLock(self.lock) { self.inFlightTasks.removeValue(forKey: key) } }
                return try await self.performFetch(target: target, filters: filters, reason: reason)
            }
            inFlightTasks[key] = newTask
            return newTask
        }

        return try await task.value
    }

    private func performFetch(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> [EvaluationResult] {
        guard let result = await provider.fetch(target: target, filters: filters) else {
            Logger.d("EvaluationFetchCoordinator: Fetch failed for \(target.matchingKey) (reason: \(reason))")
            throw EvaluationFetchError.fetchFailed
        }

        if let storage {
            Task { // Non-blocking persistence
                let change = EvaluationChange(
                    target: target,
                    changeNumber: result.till ?? -1,
                    evaluations: result.evaluations
                )

                try? await storage.upsert(change: change)
            }
        }

        Logger.d("EvaluationFetchCoordinator: Fetched \(result.evaluations.count) evaluations for \(target.matchingKey) (reason: \(reason))")
        return result.evaluations
    }
}
