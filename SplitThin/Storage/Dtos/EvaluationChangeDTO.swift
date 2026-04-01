import Foundation

struct EvaluationChangeDTO: DynamicCodable, Sendable {
    let changeNumber: Int64?
    let evaluations: [String: EvaluationResultDTO]?

    init(changeNumber: Int64? = -1, evaluations: [String: EvaluationResultDTO]? = [:]) {
        self.changeNumber = changeNumber
        self.evaluations = evaluations
    }

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any] else {
            throw JsonError.invalidData
        }
        changeNumber = dict["changeNumber"] as? Int64 ?? -1

        if let evaluationsDict = dict["evaluations"] as? [String: Any] {
            evaluations = try evaluationsDict.mapValues { value in
                try EvaluationResultDTO(jsonObject: value)
            }
        } else {
            evaluations = [:]
        }
    }

    func toJsonObject() -> Any {
        var dict = [String: Any]()
        dict["changeNumber"] = changeNumber
        if let evaluations {
            dict["evaluations"] = evaluations.mapValues { $0.toJsonObject() }
        }
        return dict
    }
}
