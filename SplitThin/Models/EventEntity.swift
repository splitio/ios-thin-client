import Foundation

public struct EventEntity: Sendable {
    public let trafficType: String
    public let eventType: String
    public let value: Double?
    public let properties: [String: String]?
    public let timestamp: Date

    public init(trafficType: String, eventType: String, value: Double? = nil, properties: [String: String]? = nil, timestamp: Date = Date()) {
        self.trafficType = trafficType
        self.eventType = eventType
        self.value = value
        self.properties = properties
        self.timestamp = timestamp
    }
}
