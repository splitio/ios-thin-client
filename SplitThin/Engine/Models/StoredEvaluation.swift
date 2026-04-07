import Foundation

struct StoredEvaluation: Sendable {
    let evaluationResult: EvaluationResult
    let flagSets: [String]

    init(evaluationResult: EvaluationResult, flagSets: [String]) {
        self.evaluationResult = evaluationResult
        self.flagSets = flagSets
    }
}
