//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

public struct EventEntity: DynamicEncodable, @unchecked Sendable {
    let id: UUID
    let trafficType: String
    let eventType: String
    let value: Double?
    let properties: [String: Any]?
    let timestamp: Date

    init(id: UUID = UUID(), trafficType: String, eventType: String, value: Double? = nil, properties: [String: Any]? = nil, timestamp: Date = Date()) {
        self.id = id
        self.trafficType = trafficType
        self.eventType = eventType
        self.value = value
        self.properties = properties
        self.timestamp = timestamp
    }

    func toJsonObject() -> Any {
        var dict = [String: Any]()
        dict["eventTypeId"] = eventType
        dict["trafficTypeName"] = trafficType
        dict["timestamp"] = Int64(timestamp.timeIntervalSince1970 * 1000)
        if let value {
            dict["value"] = value
        }
        if let properties, !properties.isEmpty {
            dict["properties"] = properties
        }
        return dict
    }
}
