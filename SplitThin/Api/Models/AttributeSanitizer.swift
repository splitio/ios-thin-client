//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

enum AttributeSanitizer {

    static func sanitize(_ attributes: [String: Any]?) -> [String: Any]? {
        guard let attributes else { return nil }

        var sanitized = [String: Any](minimumCapacity: attributes.count)
        for (name, value) in attributes {
            guard isSerializable(value), !containsMap(value) else {
                Logger.w("Target attributes - discarded '\(name)': value must be a String, Number, " +
                         "Boolean, or a list of those (nested maps and non-serializable values are not allowed)")
                continue
            }
            sanitized[name] = value
        }
        return sanitized
    }

    // `isValidJSONObject` only accepts a top-level array/dictionary, so wrap the value to probe a
    // single attribute. Scalars, lists and NSNull all resolve correctly through the array form.
    private static func isSerializable(_ value: Any) -> Bool {
        JSONSerialization.isValidJSONObject([value])
    }

    private static func containsMap(_ value: Any) -> Bool {
        if value as? [AnyHashable: Any] != nil { return true }
        if let array = value as? [Any] { return array.contains(where: containsMap) }
        return false
    }
}
