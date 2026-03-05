import Foundation

public struct EvaluationResult: Sendable {
    public let flag: String
    public let treatment: String
    public let label: String?
    public let changeNumber: Int64?

    public init(flag: String, treatment: String, label: String? = nil, changeNumber: Int64? = nil) {
        self.flag = flag
        self.treatment = treatment
        self.label = label
        self.changeNumber = changeNumber
    }
}
