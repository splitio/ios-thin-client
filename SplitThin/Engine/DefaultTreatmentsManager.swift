import Foundation

protocol TreatmentsManager: Sendable {
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) -> EvaluationResult
    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult]
}

final class DefaultTreatmentsManager: TreatmentsManager, @unchecked Sendable {

    private let target: Target
    private let evaluationRepository: EvaluationRepository

    init(target: Target, evaluationRepository: EvaluationRepository) {
        self.target = target
        self.evaluationRepository = evaluationRepository
    }

    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) -> EvaluationResult {
        evaluationRepository.getEvaluation(flag: flag)?.evaluationResult ?? EvaluationResult(flag: flag, treatment: "control", flagSets: [])
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult] {
        let storedEvaluations = evaluationRepository.getEvaluations(flags: flags)
        let resultsByFlag = Dictionary(uniqueKeysWithValues: storedEvaluations.map { ($0.evaluationResult.flag, $0.evaluationResult) })
        return flags.map { resultsByFlag[$0] ?? EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult] {
        evaluationRepository.getEvaluationsByFlagSets(flagSets).map { $0.evaluationResult }
    }
}
