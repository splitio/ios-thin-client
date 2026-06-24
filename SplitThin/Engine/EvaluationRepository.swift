//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol EvaluationRepository: Sendable {
    func getEvaluation(flag: String, target: Target) -> StoredEvaluation?
    func getEvaluations(flags: [String], target: Target) -> [StoredEvaluation]
    func getEvaluationsByFlagSets(_ flagSets: [String], target: Target) -> [StoredEvaluation]
    func getFlagNames(target: Target) -> [String]
    func setTarget(_ target: Target)
    @discardableResult
    func update(_ evaluations: [EvaluationResult], for target: Target) -> [String]
    @discardableResult
    func applyFetched(_ result: FetchResult, for target: Target) -> [String] // Applies a fetch result to the in-memory cache, honoring `shouldApplyToCache` so an up-to-date (empty) response never wipes existing data.
    @discardableResult
    func loadFromCache(_ evaluations: [EvaluationResult], for target: Target) -> [String]
    @discardableResult
    func initialize(target: Target) async throws -> FetchResult
}

final class DefaultEvaluationRepository: EvaluationRepository, @unchecked Sendable {

    private let fetchCoordinator: EvaluationFetchCoordinator
    private let evaluationFilters: EvaluationFilters?
    private let readStorage: EvaluationReadStorage?

    private var cache = [Key: [String: StoredEvaluation]]()
    private let lock = NSLock()

    init(fetchCoordinator: EvaluationFetchCoordinator, evaluationFilters: EvaluationFilters?, readStorage: EvaluationReadStorage? = nil) {
        self.fetchCoordinator = fetchCoordinator
        self.evaluationFilters = evaluationFilters
        self.readStorage = readStorage
    }

    func getEvaluation(flag: String, target: Target) -> StoredEvaluation? {
        withLock(lock) { cache[target.key]?[flag] }
    }

    func getEvaluations(flags: [String], target: Target) -> [StoredEvaluation] {
        withLock(lock) {
            let targetCache = cache[target.key] ?? [:]
            return flags.compactMap { targetCache[$0] }
        }
    }

    func getEvaluationsByFlagSets(_ flagSets: [String], target: Target) -> [StoredEvaluation] {
        withLock(lock) {
            let targetCache = cache[target.key] ?? [:]
            return targetCache.values.filter { stored in
                !Set(stored.flagSets).isDisjoint(with: flagSets)
            }
        }
    }

    func getFlagNames(target: Target) -> [String] {
        withLock(lock) { Array((cache[target.key] ?? [:]).keys) }
    }

    func setTarget(_ target: Target) {
        Task { [weak self] in
            guard let self else { return }

            // Hydrate the new target from persisted storage first, so reads during the in-flight
            // window return cached treatments instead of control. Sequenced before the fetch so
            // the authoritative result always wins (and an up-to-date result won't wipe it).
            if let readStorage = self.readStorage {
                let cached = await readStorage.getAll(target: target)
                if !cached.isEmpty {
                    self.update(cached, for: target)
                }
            }

            do {
                let result = try await self.fetchCoordinator.fetchIfNeeded(target: target, filters: self.evaluationFilters, reason: .targetSwitch)
                self.applyFetched(result, for: target)
            } catch {
                Logger.e("EvaluationRepository: Failed to fetch evaluations for target \(target.matchingKey): \(error)")
            }
        }
    }

    @discardableResult
    func applyFetched(_ result: FetchResult, for target: Target) -> [String] {
        guard result.shouldApplyToCache else { return [] }
        return update(result.evaluations, for: target)
    }

    @discardableResult
    func loadFromCache(_ evaluations: [EvaluationResult], for target: Target) -> [String] {
        withLock(lock) {
            // This disk load races the initial network fetch. Apply the
            // persisted data only if the network hasn't written this target yet.
            guard cache[target.key] == nil else { return [] }
            return updateLocked(evaluations: evaluations, for: target)
        }
    }

    @discardableResult
    func initialize(target: Target) async throws -> FetchResult {
        let result = try await fetchCoordinator.fetchIfNeeded(target: target, filters: evaluationFilters, reason: .initialization)
        applyFetched(result, for: target)
        return result
    }

    @discardableResult
    func update(_ evaluations: [EvaluationResult], for target: Target) -> [String] {
        withLock(lock) { updateLocked(evaluations: evaluations, for: target) }
    }

    func clear() {
        withLock(lock) {
            cache.removeAll()
        }
    }

    // MARK: - Private

    /// Replaces the cached evaluations for `target` and returns the changed flag names.
    /// Caller must hold `lock`.
    private func updateLocked(evaluations: [EvaluationResult], for target: Target) -> [String] {
        let userKey = target.key
        let old = cache[userKey] ?? [:]
        var newCache = [String: StoredEvaluation]()
        var changed = [String]()

        // 1. Add new evaluations to cache
        for evaluation in evaluations {
            newCache[evaluation.flag] = StoredEvaluation(evaluationResult: evaluation, flagSets: evaluation.flagSets)
            if let existing = old[evaluation.flag] {
                if !Self.isUnchanged(evaluation, existing) { changed.append(evaluation.flag) }
            } else {
                changed.append(evaluation.flag)
            }
        }

        // 2 Flags present before but absent now were removed by the server.
        for flag in old.keys where newCache[flag] == nil {
            changed.append(flag)
        }

        // 3. Update cache and return changed flags
        cache[userKey] = newCache
        return changed
    }

    private static func isUnchanged(_ new: EvaluationResult, _ old: StoredEvaluation) -> Bool {
        new.treatment == old.evaluationResult.treatment
            && new.config == old.evaluationResult.config
            && Set(new.flagSets) == Set(old.flagSets)
    }
}
