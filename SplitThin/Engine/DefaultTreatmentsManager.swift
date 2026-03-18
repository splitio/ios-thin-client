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
        evaluationRepository.getTreatment(flag: flag) ?? EvaluationResult(flag: flag, treatment: "control", flagSets: [])
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult] {
        let results = evaluationRepository.getTreatments(flags: flags)
        let resultsByFlag = Dictionary(uniqueKeysWithValues: results.map { ($0.flag, $0) })
        return flags.map { resultsByFlag[$0] ?? EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult] {
        evaluationRepository.getTreatmentsByFlagSets(flagSets)
    }
}
