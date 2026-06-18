//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Tracker

final class ThinEventValidator: TrackerEventValidator {

    private let maxKeyLength = 250
    private let eventNamePattern = "^[a-zA-Z0-9][-_.:a-zA-Z0-9]{0,79}$"

    func validate(key: String?, trafficTypeName: String?, eventTypeId: String?, value: Double?, properties: [String: Any]?, isSdkReady: Bool) -> TrackerValidationError? {

        guard let key, !key.isEmpty else {
            return TrackerValidationError(isError: true, message: "You passed a null or empty key, the key must be a non-empty string")
        }

        if key.count > maxKeyLength {
            return TrackerValidationError(isError: true, message: "Matching key too long - must be \(maxKeyLength) characters or less")
        }

        guard let trafficType = trafficTypeName, !trafficType.isEmpty else {
            return TrackerValidationError(isError: true, message: "You passed a null or empty traffic type, traffic type must be a non-empty strin. Dropping event.")
        }

        if trafficType != trafficType.lowercased() {
            return TrackerValidationError(isError: false, message: "Traffic type should be all lowercase - converting string to lowercase")
        }

        guard let eventType = eventTypeId, !eventType.isEmpty else {
            return TrackerValidationError(isError: true, message: "You passed a null or empty event type, event type must be a non-empty string")
        }

        if !isEventNameValid(eventType) {
            return TrackerValidationError(isError: true, message: "You passed \(eventType), event name must adhere to the regular expression \(eventNamePattern). This means an event name must be alphanumeric, cannot be more than 80 characters long, and can only include a dash, underscore, period, or colon as separators of alphanumeric characters")
        }

        return nil
    }

    private func isEventNameValid(_ name: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: eventNamePattern, options: .caseInsensitive) else {
            return false
        }

        let range = regex.rangeOfFirstMatch(in: name, options: [], range: NSRange(location: 0, length: name.count))
        return range.location == 0 && range.length == name.count
    }
}
