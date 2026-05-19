//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

struct EvaluationChangeDTO: DynamicCodable, @unchecked Sendable {
    let changeNumber: Int64?
    let attributes: [String: Any]?
    let evaluations: [String: EvaluationResultDTO]?

    init(changeNumber: Int64? = -1, attributes: [String: Any]? = nil, evaluations: [String: EvaluationResultDTO]? = [:]) {
        self.changeNumber = changeNumber
        self.attributes = attributes
        self.evaluations = evaluations
    }

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any] else {
            throw JsonError.invalidData
        }
        changeNumber = dict["changeNumber"] as? Int64 ?? -1
        attributes = dict["attributes"] as? [String: Any]

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
        if let attributes {
            dict["attributes"] = attributes
        }
        if let evaluations {
            dict["evaluations"] = evaluations.mapValues { $0.toJsonObject() }
        }
        return dict
    }
}
