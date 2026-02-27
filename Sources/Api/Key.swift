import Foundation

public struct Key: Hashable, Codable {
    public let matchingKey: String
    public let bucketingKey: String?

    public init(matchingKey: String, bucketingKey: String? = nil) {
        self.matchingKey = matchingKey
        self.bucketingKey = bucketingKey
    }
}

