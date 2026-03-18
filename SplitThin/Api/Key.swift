import Foundation

public final class Key: Hashable, @unchecked Sendable {

    let matchingKey: String
    let bucketingKey: String?

    public init(matchingKey: String, bucketingKey: String? = nil) {
        self.matchingKey = matchingKey
        self.bucketingKey = bucketingKey
    }

    public static func == (lhs: Key, rhs: Key) -> Bool {
        lhs.matchingKey == rhs.matchingKey
        && lhs.bucketingKey == rhs.bucketingKey
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(matchingKey)
        hasher.combine(bucketingKey)
    }
}
