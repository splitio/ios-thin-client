//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Tracker

final class ThinPropertyValidator: TrackerPropertyValidator {

    private let maxPropertyBytes = 32768
    private let maxPropertyCount = 300

    func validate(properties: [String: Any]?, initialSizeInBytes: Int, validationTag: String) -> TrackerPropertyResult {
        var totalSize = initialSizeInBytes

        guard let props = properties else {
            return .valid(properties: nil, sizeInBytes: totalSize)
        }

        var validated = props

        for (key, value) in props {
            if !isPrimitive(value) {
                validated[key] = NSNull()
            }

            totalSize += estimateSize(key) + estimateSize(value as? String)
            if totalSize > maxPropertyBytes {
                return .invalid(message: "The maximum size allowed for the properties is 32kb. Current property is \(key). Validation failed", sizeInBytes: totalSize)
            }
        }

        return .valid(properties: validated, sizeInBytes: totalSize)
    }

    private func isPrimitive(_ value: Any) -> Bool {
        value is String || value is Int || value is Double || value is Float || value is Bool
    }

    private func estimateSize(_ value: String?) -> Int {
        guard let value else { return 0 }

        return MemoryLayout.size(ofValue: value) * value.count
    }
}
