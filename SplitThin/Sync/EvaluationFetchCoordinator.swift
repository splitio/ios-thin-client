//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

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

struct FetchResult: Sendable {
    let evaluations: [EvaluationResult]
    let changeNumber: Int64?

    /// Whether this result should replace the in-memory cache. `false` for an up-to-date
    /// response (server returned empty because nothing changed), so applying it would wipe
    /// existing data. Defaults to `true` to preserve behavior for callers that don't set it.
    let shouldApplyToCache: Bool

    init(evaluations: [EvaluationResult], changeNumber: Int64?, shouldApplyToCache: Bool = true) {
        self.evaluations = evaluations
        self.changeNumber = changeNumber
        self.shouldApplyToCache = shouldApplyToCache
    }
}

private struct FetchKey: Hashable {
    let target: Target
    let filters: EvaluationFilters?
}

protocol EvaluationFetchCoordinator: Sendable {
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult
    func refetchAll(delay: RefetchDelay) async
    func refetchKeys(_ matchingKeys: Set<String>, delay: RefetchDelay) async

    // Bridge with clients
    func registerOnUpdateAction(for key: Key, action: @escaping (FetchResult) -> Void)
    func unregisterOnUpdateAction(for key: Key)
    func unregister(target: Target)

    /// The matching keys that have been registered via fetchIfNeeded (and not unregistered).
    var registeredMatchingKeys: [String] { get }
}

final class DefaultEvaluationFetchCoordinator: EvaluationFetchCoordinator, @unchecked Sendable {

    private let provider: EvaluationProvider
    private let observer: Observer // For logging & telemetry
    private let storage: EvaluationWriteStorage?
    private let readStorage: EvaluationReadStorage?

    // Called after a successful fetch, per key
    private var onUpdateActions = [Key: (FetchResult) -> Void]()

    // For requests coordination
    private var inFlightTasks = [FetchKey: Task<FetchResult, Error>]()
    private var fetchedKeys = Set<FetchKey>()
    private let lock = NSLock()

    init(provider: EvaluationProvider, observer: Observer, storage: EvaluationWriteStorage? = nil, readStorage: EvaluationReadStorage? = nil) {
        self.provider = provider
        self.observer = observer
        self.storage = storage
        self.readStorage = readStorage
    }

    func registerOnUpdateAction(for key: Key, action: @escaping (FetchResult) -> Void) {
        withLock(lock) { onUpdateActions[key] = action }
    }

    func unregisterOnUpdateAction(for key: Key) {
        withLock(lock) { onUpdateActions.removeValue(forKey: key) }
    }

    func unregister(target: Target) {
        withLock(lock) {
            fetchedKeys = fetchedKeys.filter { $0.target != target }
        }
    }

    var registeredMatchingKeys: [String] {
        withLock(lock) { fetchedKeys.map { $0.target.matchingKey } }
    }

    @discardableResult
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult {
        observer.notify(event: .evalFetchRequested(reason: reason))

        let key = FetchKey(target: target, filters: filters)

        let task: Task<FetchResult, Error> = withLock(lock) {
            if reason == .initialization || reason == .targetSwitch {
                fetchedKeys.insert(key)
            }

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

    func refetchAll(delay: RefetchDelay = .none) async {
        let keys = withLock(lock) { fetchedKeys }
        await fetchKeys(keys, delay: delay)
    }

    func refetchKeys(_ matchingKeys: Set<String>, delay: RefetchDelay = .none) async {
        let keys = withLock(lock) { fetchedKeys }
        let filtered = keys.filter { matchingKeys.contains($0.target.matchingKey) }
        await fetchKeys(filtered, delay: delay)
    }

    // MARK: - Private

    private func fetchKeys(_ keys: Set<FetchKey>, delay: RefetchDelay) async {
        for key in keys {
            let keyDelay = delay.delay(forKey: key.target.matchingKey)
            if keyDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(keyDelay * 1_000_000_000))
            }
            _ = try? await fetchIfNeeded(target: key.target, filters: key.filters, reason: .push)
        }
    }

    private func performFetch(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult {
        observer.notify(event: .evalFetchStarted(reason: reason))

        let storedChangeNumber = await readStorage?.lastChangeNumber(target: target) ?? -1

        let result: EvaluationsResult

        // Fetch 
        do {
            guard let fetched = try await provider.fetch(target: target, filters: filters) else {
                Logger.d("EvaluationFetchCoordinator: Fetch failed for \(target.matchingKey) (reason: \(reason))")
                observer.notify(event: .evalFetchFailed)
                throw EvaluationFetchError.fetchFailed
            }
            result = fetched
        } catch CredentialFetcherError.unauthorized {
            observer.notify(event: .authUnauthorized)
            throw CredentialFetcherError.unauthorized
        }

        let changeNumber = result.till ?? -1
        observer.notify(event: .evalFetchSucceeded(changeNumber: changeNumber))

        // When till == stored, the server confirms we're up to date
        // and returns an empty evaluations array. Persisting it would erase existing data.
        let biggerChangeNumber = changeNumber > storedChangeNumber

        // Persist 
        if biggerChangeNumber {
            observer.notify(event: .evalStorageWriteScheduled)

            Task { [self] in // Non-blocking persistence
                do {
                    try await self.storage?.upsert(change: EvaluationChange(target: target, changeNumber: changeNumber, evaluations: result.evaluations))
                    self.observer.notify(event: .evalStorageWriteSucceeded)
                    observer.notify(event: .evalStorageUpdated(names: result.evaluations.map { $0.flag }))
                } catch {
                    self.observer.notify(event: .evalStorageWriteFailed)
                }
            }
        }

        // Edge case: Server has no flags yet (since/till == -1, no evaluations).
        // Nothing to persist, but the SDK must still be marked ready.
        let isEmptyAccount = result.since == -1 && changeNumber == -1 && result.evaluations.isEmpty

        // Apply to the in-memory cache unless this is an up-to-date *empty* response (server returned
        // nothing because nothing changed) — applying that would wipe existing data. Non-empty results
        // are always applied; an empty result is applied only when it carries new data (all flags
        // removed) or represents an empty account.
        let shouldApplyToCache = result.evaluations.notEmpty || biggerChangeNumber || isEmptyAccount
        
        // Trigger SDK_UPDATE
        if (reason == .push || reason == .targetSwitch), shouldApplyToCache {
            let updateAction = withLock(lock) { onUpdateActions[target.key] }
            updateAction?(FetchResult(evaluations: result.evaluations, changeNumber: changeNumber, shouldApplyToCache: true)) // Notifies the eventsManager of the client
        }

        Logger.d("EvaluationFetchCoordinator: Fetched \(result.evaluations.count) evaluations for \(target.matchingKey) (reason: \(reason), hasNewData: \(biggerChangeNumber))")
        return FetchResult(evaluations: result.evaluations, changeNumber: changeNumber, shouldApplyToCache: shouldApplyToCache)
    }
}
