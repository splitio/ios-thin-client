import Foundation

protocol EvaluationRepository: Sendable {
    func getEvaluation(flag: String) -> StoredEvaluation?
    func getEvaluations(flags: [String]) -> [StoredEvaluation]
    func getEvaluationsByFlagSets(_ flagSets: [String]) -> [StoredEvaluation]
    func getFlagNames() -> [String]
    func setTarget(_ target: Target)
    func update(_ evaluations: [EvaluationResult])
    func clear()
}

final class DefaultEvaluationRepository: EvaluationRepository, @unchecked Sendable {

    private var currentTarget: Target
    private var cachedEvaluations = [String: StoredEvaluation]()
    private let lock = NSLock()

    init(target: Target) {
        self.currentTarget = target
    }

    func getEvaluation(flag: String) -> StoredEvaluation? {
        withLock(lock) { cachedEvaluations[flag] }
    }

    func getEvaluations(flags: [String]) -> [StoredEvaluation] {
        withLock(lock) {
            flags.compactMap { cachedEvaluations[$0] }
        }
    }

    func getEvaluationsByFlagSets(_ flagSets: [String]) -> [StoredEvaluation] {
        withLock(lock) {
            cachedEvaluations.values.filter { stored in
                !Set(stored.flagSets).isDisjoint(with: flagSets)
            }
        }
    }

    func getFlagNames() -> [String] {
        withLock(lock) { Array(cachedEvaluations.keys) }
    }

    func setTarget(_ target: Target) {
        withLock(lock) {
            currentTarget = target
            cachedEvaluations.removeAll()
        }
    }

    func update(_ evaluations: [EvaluationResult]) {
        withLock(lock) {
            for evaluation in evaluations {
                let stored = StoredEvaluation(evaluationResult: evaluation, flagSets: evaluation.flagSets)
                cachedEvaluations[evaluation.flag] = stored
            }
        }
    }

    func clear() {
        withLock(lock) { cachedEvaluations.removeAll() }
    }
}
