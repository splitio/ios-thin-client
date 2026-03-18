import Foundation
@testable import SplitThin

final class TreatmentsManagerMock: TreatmentsManager, @unchecked Sendable {

    var getTreatmentResult: EvaluationResult?
    var getTreatmentsResult: [EvaluationResult] = []
    var getTreatmentsByFlagSetsResult: [EvaluationResult] = []

    var getTreatmentCallCount = 0
    var getTreatmentsCallCount = 0
    var getTreatmentsByFlagSetsCallCount = 0

    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult {
        getTreatmentCallCount += 1
        return getTreatmentResult ?? EvaluationResult(flag: flag, treatment: "control")
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        getTreatmentsCallCount += 1
        return getTreatmentsResult.isEmpty
            ? flags.map { EvaluationResult(flag: $0, treatment: "control") }
            : getTreatmentsResult
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        getTreatmentsByFlagSetsCallCount += 1
        return getTreatmentsByFlagSetsResult
    }
}
