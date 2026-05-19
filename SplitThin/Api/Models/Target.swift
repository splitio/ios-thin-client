//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

public struct Target: Hashable, @unchecked Sendable {

    let key: Key
    let attributes: [String: Any]?
    let trafficType: String?

    var matchingKey: String { key.matchingKey }
    var bucketingKey: String? { key.bucketingKey }

    public init(key: Key, attributes: [String: Any]? = nil, trafficType: String? = nil) {
        self.key = key
        self.attributes = attributes
        self.trafficType = trafficType
    }

    public init(matchingKey: String, bucketingKey: String? = nil, attributes: [String: Any]? = nil, trafficType: String? = nil) {
        self.key = Key(matchingKey: matchingKey, bucketingKey: bucketingKey)
        self.attributes = attributes
        self.trafficType = trafficType
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(trafficType)
        if let attributes {
            hasher.combine((attributes as NSDictionary).hash)
        }
    }

    // MARK: - Equatable

    public static func == (lhs: Target, rhs: Target) -> Bool {
        lhs.key == rhs.key
            && attributesEqual(lhs.attributes, rhs.attributes)
            && lhs.trafficType == rhs.trafficType
    }

    private static func attributesEqual(_ lhs: [String: Any]?, _ rhs: [String: Any]?) -> Bool {
        switch (lhs, rhs) {
            case (nil, nil):
                true
            case (nil, _), (_, nil):
                false
            case let (l?, r?):
                NSDictionary(dictionary: l).isEqual(to: r)
        }
    }
}
