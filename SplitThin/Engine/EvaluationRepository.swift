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
    func initialize(target: Target) async throws -> FetchResult
}

final class DefaultEvaluationRepository: EvaluationRepository, @unchecked Sendable {

    private let fetchCoordinator: EvaluationFetchCoordinator
    private let evaluationFilters: EvaluationFilters?

    private var cache = [Key: [String: StoredEvaluation]]()
    private let lock = NSLock()

    init(fetchCoordinator: EvaluationFetchCoordinator, evaluationFilters: EvaluationFilters?) {
        self.fetchCoordinator = fetchCoordinator
        self.evaluationFilters = evaluationFilters
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
            do {
                let result = try await self.fetchCoordinator.fetchIfNeeded(target: target, filters: self.evaluationFilters, reason: .targetSwitch)
                self.update(result.evaluations, for: target)
            } catch {
                Logger.e("EvaluationRepository: Failed to fetch evaluations for target \(target.matchingKey): \(error)")
            }
        }
    }

    @discardableResult
    func initialize(target: Target) async throws -> FetchResult {
        let result = try await fetchCoordinator.fetchIfNeeded(target: target, filters: evaluationFilters, reason: .initialization)
        update(result.evaluations, for: target)
        return result
    }

    @discardableResult
    func update(_ evaluations: [EvaluationResult], for target: Target) -> [String] {
        let userKey = target.key
        return withLock(lock) {
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
    }

    func clear() {
        withLock(lock) { cache.removeAll() }
    }

    // MARK: - Private

    private static func isUnchanged(_ new: EvaluationResult, _ old: StoredEvaluation) -> Bool {
        new.treatment == old.evaluationResult.treatment
            && new.config == old.evaluationResult.config
            && Set(new.flagSets) == Set(old.flagSets)
    }
}
