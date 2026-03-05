import Foundation

public struct Target: Hashable, Sendable {
    public let matchingKey: String
    public let bucketingKey: String?
    public let attributes: [String: String]?
    public let trafficType: String?

    public init(matchingKey: String, bucketingKey: String? = nil, attributes: [String: String]? = nil, trafficType: String? = nil) {
        self.matchingKey = matchingKey
        self.bucketingKey = bucketingKey
        self.attributes = attributes
        self.trafficType = trafficType
    }
}
