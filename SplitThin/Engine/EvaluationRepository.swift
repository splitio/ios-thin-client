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
    func update(_ evaluations: [EvaluationResult], for target: Target)
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
                self.cacheEvaluations(result.evaluations, for: target)
            } catch {
                Logger.e("EvaluationRepository: Failed to fetch evaluations for target \(target.matchingKey): \(error)")
            }
        }
    }

    @discardableResult
    func initialize(target: Target) async throws -> FetchResult {
        let result = try await fetchCoordinator.fetchIfNeeded(target: target, filters: evaluationFilters, reason: .initialization)
        cacheEvaluations(result.evaluations, for: target)
        return result
    }

    func update(_ evaluations: [EvaluationResult], for target: Target) {
        cacheEvaluations(evaluations, for: target)
    }

    func clear() {
        withLock(lock) { cache.removeAll() }
    }

    // MARK: - Private

    private func cacheEvaluations(_ evaluations: [EvaluationResult], for target: Target) {
        guard !evaluations.isEmpty else { return }

        let userKey = target.key
        withLock(lock) {
            var targetCache = cache[userKey] ?? [:]
            for evaluation in evaluations {
                let stored = StoredEvaluation(evaluationResult: evaluation, flagSets: evaluation.flagSets)
                targetCache[evaluation.flag] = stored
            }
            cache[userKey] = targetCache
        }
    }
}
