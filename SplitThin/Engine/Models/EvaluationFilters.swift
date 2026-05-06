//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

public struct EvaluationFilters: Sendable, Hashable {
    public let flagNames: [String]?
    public let flagSets: [String]?
    public let withDynamicConfig: Bool

    public init(flagNames: [String]? = nil, flagSets: [String]? = nil, withDynamicConfig: Bool = false) {
        self.flagNames = flagNames
        self.flagSets = flagSets
        self.withDynamicConfig = withDynamicConfig
    }
}
