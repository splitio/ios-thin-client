import Foundation

public protocol EvaluationRepository: Sendable {
    func getTreatment(flag: String) -> EvaluationResult?
    func getTreatments(flags: [String]) -> [EvaluationResult]
    func getTreatmentsByFlagSets(_ flagSets: [String]) -> [EvaluationResult]
    func getFlagNames() -> [String]
    func setTarget(_ target: Target)
    func update(_ evaluations: [EvaluationResult])
    func clear()
}

final class DefaultEvaluationRepository: EvaluationRepository, @unchecked Sendable {

    private let splitManager: DefaultSplitManager?

    private var currentTarget: Target
    private var cachedEvaluations = [String: EvaluationResult]()
    private let lock = NSLock()

    init(target: Target, splitManager: DefaultSplitManager? = nil) {
        self.currentTarget = target
        self.splitManager = splitManager
    }

    func getTreatment(flag: String) -> EvaluationResult? {
        withLock(lock) { cachedEvaluations[flag] }
    }

    func getTreatments(flags: [String]) -> [EvaluationResult] {
        withLock(lock) {
            flags.compactMap { cachedEvaluations[$0] }
        }
    }

    func getTreatmentsByFlagSets(_ flagSets: [String]) -> [EvaluationResult] {
        withLock(lock) {
            cachedEvaluations.values.filter { evaluation in
                !Set(evaluation.flagSets).isDisjoint(with: flagSets)
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
                cachedEvaluations[evaluation.flag] = evaluation
            }
            splitManager?.updateFlags(evaluations.map { $0.flag })
        }
    }

    func clear() {
        withLock(lock) { cachedEvaluations.removeAll() }
    }
}
