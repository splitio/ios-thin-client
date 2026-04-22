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

struct FetchResult: Sendable {
    let evaluations: [EvaluationResult]
    let changeNumber: Int64?
}

private struct FetchKey: Hashable {
    let target: Target
    let filters: EvaluationFilters?
}

protocol EvaluationFetchCoordinator: Sendable {
    /// Coordinates fetch requests so only one relevant fetch runs at a time.
    /// Returns the fetched evaluations (can be empty on success). Throws on failure.
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult
}

final class DefaultEvaluationFetchCoordinator: EvaluationFetchCoordinator, @unchecked Sendable {

    private let provider: EvaluationProvider
    private let observer: Observer // For logging & telemetry
    private let storage: EvaluationWriteStorage?

    private var inFlightTasks = [FetchKey: Task<FetchResult, Error>]()
    private let lock = NSLock()

    init(provider: EvaluationProvider, observer: Observer, storage: EvaluationWriteStorage? = nil) {
        self.provider = provider
        self.observer = observer
        self.storage = storage
    }

    @discardableResult
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult {
        observer.notify(event: .evalFetchRequested(reason: reason))

        let key = FetchKey(target: target, filters: filters)

        // Atomic tasks
        let task: Task<FetchResult, Error> = withLock(lock) {

            // 1. Check for deduplications
            if let existing = inFlightTasks[key] {
                Logger.d("EvaluationFetchCoordinator: Awaiting in-flight fetch for \(target.matchingKey) (reason: \(reason))")
                observer.notify(event: .evalFetchDeduped(reason: reason))
                return existing
            }

            // 2. Create request and add to the list (for deduplication)
            let newTask = Task<FetchResult, Error> { [weak self] in
                guard let self else { throw EvaluationFetchError.fetchFailed }
                defer { withLock(self.lock) { self.inFlightTasks.removeValue(forKey: key) } }
                return try await self.performFetch(target: target, filters: filters, reason: reason)
            }
            inFlightTasks[key] = newTask
            return newTask
        }

        return try await task.value
    }

    private func performFetch(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult {
        observer.notify(event: .evalFetchStarted(reason: reason))

        guard let result = await provider.fetch(target: target, filters: filters) else {
            Logger.d("EvaluationFetchCoordinator: Fetch failed for \(target.matchingKey) (reason: \(reason))")
            observer.notify(event: .evalFetchFailed)
            throw EvaluationFetchError.fetchFailed
        }

        let changeNumber = result.till
        observer.notify(event: .evalFetchSucceeded(changeNumber: changeNumber ?? -1))

        if let storage {


            observer.notify(event: .evalStorageWriteScheduled)
            
            Task { // Non-blocking persistence
                do {
                    try await storage.upsert(change: EvaluationChange(target: target, changeNumber: changeNumber ?? -1, evaluations: result.evaluations))
                    self.observer.notify(event: .evalStorageWriteSucceeded)
                } catch {
                    self.observer.notify(event: .evalStorageWriteFailed)
                }
            }
        }

        observer.notify(event: .evalStorageUpdated(names: result.evaluations.map { $0.flag }))

        Logger.d("EvaluationFetchCoordinator: Fetched \(result.evaluations.count) evaluations for \(target.matchingKey) (reason: \(reason))")
        return FetchResult(evaluations: result.evaluations, changeNumber: changeNumber)
    }
}
