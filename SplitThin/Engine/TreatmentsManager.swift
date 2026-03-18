import Foundation

protocol TreatmentsManager: Sendable {
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult
    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]
}
