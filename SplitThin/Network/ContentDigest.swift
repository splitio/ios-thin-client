//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

/// Computes the `X-Harness-FME-Content-Digest` header value for a Target.
///
/// Format: `murmur128x86(matchingKey:bucketingKey:attrsJson)` → first 64 bits → base64 (no padding).
/// - Attribute keys are sorted alphabetically; null-valued attributes are omitted.
/// - Collection values are sorted and null elements removed.
/// - Supported types: String, Number, Boolean, Collection.
enum ContentDigest {

    static func compute(for target: Target) -> String {
        let input = buildHashInput(for: target)
        let hashData = Murmur128x86.hashToData(input)
        return hashData.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    // MARK: - Private

    static func buildHashInput(for target: Target) -> String {
        let bucketingKey = target.bucketingKey ?? ""
        let attrsJson = serializeAttributes(target.attributes)
        return "\(target.matchingKey):\(bucketingKey):\(attrsJson)"
    }

    private static func serializeAttributes(_ attributes: [String: Any]?) -> String {
        guard let attributes, !attributes.isEmpty else {
            return "{}"
        }

        let pairs = attributes.keys.sorted().compactMap { key -> String? in
            guard let value = attributes[key], !(value is NSNull) else {
                return nil
            }
            return "\"\(key)\":\(serializeValue(value))"
        }

        return "{\(pairs.joined(separator: ","))}"
    }

    private static func stringRepresentation(_ value: Any) -> String {
        switch value {
            case let string as String: string
            case let bool as Bool: bool ? "true" : "false"
            case let number as NSNumber: "\(number)"
            default: "\(value)"
        }
    }

    private static func serializeValue(_ value: Any) -> String {
        switch value {
            case let string as String:
                return "\"\(string)\""
            case let bool as Bool:
                return bool ? "true" : "false"
            case let number as NSNumber:
                // NSNumber wraps Bool too — the Bool case above takes priority
                // because Swift pattern-matches `as Bool` first.
                if number.doubleValue == number.doubleValue.rounded() && !number.doubleValue.isInfinite {
                    return "\(number.intValue)"
                }
                return "\(number)"
            case let collection as [Any]:
                let sorted = collection
                    .filter { !($0 is NSNull) }
                    .sorted { stringRepresentation($0) < stringRepresentation($1) }
                    .map { serializeValue($0) }
                return "[\(sorted.joined(separator: ","))]"
            default:
                return "\"\(value)\""
        }
    }
}
