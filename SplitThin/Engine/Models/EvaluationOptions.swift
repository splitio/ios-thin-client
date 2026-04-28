//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

public struct EvaluationOptions: Sendable {
     let properties: [String: String]?

    public init(properties: [String: String]? = nil) {
        self.properties = properties
    }
}
