import Foundation

public struct EvaluationResult: Sendable, DynamicDecodable {
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

    public init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any] else {
            throw JsonError.invalidData
        }
        guard let flag = dict["flag"] as? String,
              let treatment = dict["treatment"] as? String else {
            throw JsonError.parsingFailed
        }
        self.flag = flag
        self.treatment = treatment
        self.label = dict["label"] as? String
        self.changeNumber = dict["changeNumber"] as? Int64
    }
}
