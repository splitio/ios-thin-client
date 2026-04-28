//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

public struct EventEntity: Sendable {
    let trafficType: String
    let eventType: String
    let value: Double?
    let properties: [String: String]?
    let timestamp: Date

    init(trafficType: String, eventType: String, value: Double? = nil, properties: [String: String]? = nil, timestamp: Date = Date()) {
        self.trafficType = trafficType
        self.eventType = eventType
        self.value = value
        self.properties = properties
        self.timestamp = timestamp
    }
}
