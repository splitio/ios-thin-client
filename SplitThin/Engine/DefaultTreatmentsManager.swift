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
        let result = await evaluationRepository.getTreatment(flag: flag, target: target)
        return result ?? EvaluationResult(flag: flag, treatment: "control", flagSets: [])
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        let results = await evaluationRepository.getTreatments(flags: flags, target: target)
        if results.isEmpty {
            return flags.map { EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
        }
        return results
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        let results = await evaluationRepository.getTreatmentsByFlagSets(flagSets, target: target)
        if results.isEmpty {
            return flagSets.map { EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
        }
        return results
    }
}
