import Foundation

struct EvaluationChange: Sendable {
    let target: Target
    let changeNumber: Int64
    let evaluations: [EvaluationResult]

    init(target: Target, changeNumber: Int64, evaluations: [EvaluationResult]) {
        self.target = target
        self.changeNumber = changeNumber
        self.evaluations = evaluations
    }
}
