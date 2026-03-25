import Foundation

protocol TreatmentsManager: Sendable {
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) -> EvaluationResult
    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult]
    func setTarget(_ target: Target)
}

final class DefaultTreatmentsManager: TreatmentsManager, @unchecked Sendable {

    private var target: Target
    private let evaluationRepository: EvaluationRepository
    private let lock = NSLock()

    init(target: Target, evaluationRepository: EvaluationRepository) {
        self.target = target
        self.evaluationRepository = evaluationRepository
    }

    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) -> EvaluationResult {
        let currentTarget = withLock(lock) { target }
        return evaluationRepository.getTreatment(flag: flag, target: currentTarget) ?? EvaluationResult(flag: flag, treatment: "control", flagSets: [])
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult] {
        let currentTarget = withLock(lock) { target }
        let results = evaluationRepository.getTreatments(flags: flags, target: currentTarget)
        let resultsByFlag = Dictionary(uniqueKeysWithValues: results.map { ($0.flag, $0) })
        return flags.map { resultsByFlag[$0] ?? EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult] {
        let currentTarget = withLock(lock) { target }
        return evaluationRepository.getTreatmentsByFlagSets(flagSets, target: currentTarget)
    }

    func setTarget(_ target: Target) {
        withLock(lock) { self.target = target }
        evaluationRepository.setTarget(target)
    }
}
