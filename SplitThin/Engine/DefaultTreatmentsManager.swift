import Foundation

protocol TreatmentsManager: Sendable {
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult
    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]
}

final class DefaultTreatmentsManager: TreatmentsManager, @unchecked Sendable {

    private let target: Target
    private let evaluationRepository: EvaluationRepository

    init(target: Target, evaluationRepository: EvaluationRepository) {
        self.target = target
        self.evaluationRepository = evaluationRepository
    }

    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult {
        await evaluationRepository.getTreatment(flag: flag, target: target) ?? EvaluationResult(flag: flag, treatment: "control", flagSets: [])
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        let results = await evaluationRepository.getTreatments(flags: flags, target: target)
        let resultsByFlag = Dictionary(uniqueKeysWithValues: results.map { ($0.flag, $0) })
        return flags.map { resultsByFlag[$0] ?? EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        await evaluationRepository.getTreatmentsByFlagSets(flagSets, target: target)
    }
}
