import Foundation

struct EvaluationResultDTO: DynamicCodable, Sendable {
    let treatment: String?
    let changeNumber: Int64?
    let config: String?
    let sets: [String]?

    init(treatment: String? = "control", changeNumber: Int64? = -1, config: String? = nil, sets: [String]? = []) {
        self.treatment = treatment
        self.changeNumber = changeNumber
        self.config = config
        self.sets = sets
    }

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any] else {
            throw JsonError.invalidData
        }
        treatment = dict["treatment"] as? String ?? "control"
        changeNumber = dict["changeNumber"] as? Int64 ?? -1
        config = dict["config"] as? String
        sets = dict["sets"] as? [String] ?? []
    }

    func toJsonObject() -> Any {
        var dict = [String: Any]()
        dict["treatment"] = treatment
        dict["changeNumber"] = changeNumber
        dict["config"] = config
        dict["sets"] = sets
        return dict
    }

    func toEvaluationResult(flag: String) -> EvaluationResult {
        EvaluationResult(flag: flag, treatment: treatment ?? "control", changeNumber: changeNumber, flagSets: sets ?? [], config: config)
    }
}
