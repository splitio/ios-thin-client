import Foundation

public struct Target: Hashable, Sendable {

    public let key: Key
    public let attributes: [String: String]?
    public let trafficType: String?

    public init(key: Key, attributes: [String: String]? = nil, trafficType: String? = nil) {
        self.key = key
        self.attributes = attributes
        self.trafficType = trafficType
    }

    public init(matchingKey: String, bucketingKey: String? = nil, attributes: [String: String]? = nil, trafficType: String? = nil) {
        self.key = Key(matchingKey: matchingKey, bucketingKey: bucketingKey)
        self.attributes = attributes
        self.trafficType = trafficType
    }

    public static func == (lhs: Target, rhs: Target) -> Bool {
        lhs.key == rhs.key
            && lhs.attributes == rhs.attributes
            && lhs.trafficType == rhs.trafficType
    }
}
