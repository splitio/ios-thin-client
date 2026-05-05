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
}

private struct FetchKey: Hashable {
    let target: Target
    let filters: EvaluationFilters?
}

protocol EvaluationFetchCoordinator: Sendable {
    /// Coordinates fetch requests so only one relevant fetch runs at a time.
    /// Returns the fetched evaluations (can be empty on success). Throws on failure.
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult

    /// Re-fetches all previously fetched keys with push reason.
    func refetchAll(notification: EvaluationUpdateNotification?) async
}

final class DefaultEvaluationFetchCoordinator: EvaluationFetchCoordinator, @unchecked Sendable {

    private let provider: EvaluationProvider
    private let observer: Observer // For logging & telemetry
    private let storage: EvaluationWriteStorage?
    private let delayProvider: DelayProvider

    // Called after a successful fetch, per key
    private var onUpdateActions = [Key: (FetchResult) -> Void]()

    // For requests coordination
    private var inFlightTasks = [FetchKey: Task<FetchResult, Error>]()
    private var fetchedKeys = Set<FetchKey>()
    private let lock = NSLock()

    init(provider: EvaluationProvider, observer: Observer, storage: EvaluationWriteStorage? = nil, delayProvider: @escaping DelayProvider = buildDelayProvider()) {
        self.provider = provider
        self.observer = observer
        self.storage = storage
        self.delayProvider = delayProvider
    }

    func registerOnUpdateAction(for key: Key, action: @escaping (FetchResult) -> Void) {
        withLock(lock) { onUpdateActions[key] = action }
    }

    func unregisterOnUpdateAction(for key: Key) {
        withLock(lock) { onUpdateActions.removeValue(forKey: key) }
    }

    @discardableResult
    func fetchIfNeeded(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult {
        observer.notify(event: .evalFetchRequested(reason: reason))

        let key = FetchKey(target: target, filters: filters)

        let task: Task<FetchResult, Error> = withLock(lock) {
            fetchedKeys.insert(key)

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

    func refetchAll(notification: EvaluationUpdateNotification?) async {
        let keys = withLock(lock) { fetchedKeys }
        for key in keys {
            let delay = delayProvider(notification, key.target.matchingKey)
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            _ = try? await fetchIfNeeded(target: key.target, filters: key.filters, reason: .push)
        }
    }

    private func performFetch(target: Target, filters: EvaluationFilters?, reason: FetchReason) async throws -> FetchResult {
        observer.notify(event: .evalFetchStarted(reason: reason))

        let result: EvaluationsResult
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

        if reason == .push {
            let fetchResult = FetchResult(evaluations: result.evaluations, changeNumber: changeNumber)
            let updateAction = withLock(lock) { onUpdateActions[target.key] }
            updateAction?(fetchResult) // Notifies the eventsManager of the client
        }

        observer.notify(event: .evalStorageUpdated(names: result.evaluations.map { $0.flag }))

        Logger.d("EvaluationFetchCoordinator: Fetched \(result.evaluations.count) evaluations for \(target.matchingKey) (reason: \(reason))")
        return FetchResult(evaluations: result.evaluations, changeNumber: changeNumber)
    }
}
