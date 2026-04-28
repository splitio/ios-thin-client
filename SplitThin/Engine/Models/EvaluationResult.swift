//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

public struct EvaluationResult: Sendable, DynamicDecodable {
    public let flag: String
    public let treatment: String
    public let label: String?
    public let changeNumber: Int64?
    public let flagSets: [String]
    public let config: String?

    public init(flag: String, treatment: String, label: String? = nil, changeNumber: Int64? = nil, flagSets: [String], config: String? = nil) {
        self.flag = flag
        self.treatment = treatment
        self.label = label
        self.changeNumber = changeNumber
        self.flagSets = flagSets
        self.config = config
    }

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any] else {
            throw JsonError.invalidData
        }
        guard let flag = dict["featureName"] as? String, let treatment = dict["treatment"] as? String else {
            throw JsonError.parsingFailed
        }
        self.flag = flag
        self.treatment = treatment
        label = dict["label"] as? String
        changeNumber = dict["changeNumber"] as? Int64
        flagSets = dict["sets"] as! [String]
        config = dict["config"] as? String
    }
}

// MARK: Endpoint response
struct EvaluationsResult: Sendable, DynamicDecodable {
    public let since: Int64?
    public let evaluations: [EvaluationResult]
    public let till: Int64?
    
    public init(since: Int64? = nil, evaluations: [EvaluationResult], till: Int64? = nil) {
        self.since = since
        self.evaluations = evaluations
        self.till = till
    }
    
    public init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any] else {
            throw JsonError.invalidData
        }
        since = dict["since"] as? Int64
        till = dict["till"] as? Int64

        if let evaluationsArray = dict["evaluations"] as? [[String: Any]] {
            evaluations = try evaluationsArray.map { try EvaluationResult(jsonObject: $0) }
        } else {
            evaluations = []
        }
    }
}
