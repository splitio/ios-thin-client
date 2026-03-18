import Foundation

public struct EvaluationChange: Sendable {
    public let target: Target
    public let changeNumber: Int64
    public let evaluations: [EvaluationResult]

    public init(target: Target, changeNumber: Int64, evaluations: [EvaluationResult]) {
        self.target = target
        self.changeNumber = changeNumber
        self.evaluations = evaluations
    }
}
