import Foundation

final class InMemoryEvaluationStorage: EvaluationWriteStorage, @unchecked Sendable {

    private var cache = [Key: [String: StoredEvaluation]]()
    private let lock = NSLock()

    // MARK: - EvaluationWriteStorage

    func upsert(change: EvaluationChange) async throws {
        cacheEvaluations(change.evaluations, for: change.target)
    }

    func clear(target: Target) async {
        withLock(lock) { cache[target.key] = nil }
    }

    // MARK: - Read access

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

    func cacheEvaluations(_ evaluations: [EvaluationResult], for target: Target) {
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
