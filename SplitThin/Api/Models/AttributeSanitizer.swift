//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

/// Sanitizes a target's attributes one key at a time.
///
/// The thin client forwards attributes to the server as JSON, so a "valid" attribute is simply one
/// whose value is JSON-serializable: `String`, `Number`, `Bool`, `NSNull`, or arrays/maps of those
/// (this is intentionally more permissive than the full SDK, which only allows `[String]` lists).
///
/// The raw `JSONSerialization` gate downstream is all-or-nothing: a single non-serializable value
/// (e.g. a `Date`, a `URL`, a custom object) makes the SDK drop the *entire* attribute map silently.
/// This sanitizer instead discards only the offending entries — each with a warning — keeping the
/// rest. Sanitizing once at `Target` construction guarantees what gets sent, hashed (cache
/// fingerprint) and persisted is always the same set.
enum AttributeSanitizer {

    static func sanitize(_ attributes: [String: Any]?) -> [String: Any]? {
        guard let attributes else { return nil }

        var sanitized = [String: Any](minimumCapacity: attributes.count)
        for (name, value) in attributes {
            guard isSerializable(value) else {
                Logger.w("Target attributes - discarded '\(name)': value is not JSON-serializable " +
                         "(allowed: String, Number, Boolean, or lists/maps of those)")
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
}
