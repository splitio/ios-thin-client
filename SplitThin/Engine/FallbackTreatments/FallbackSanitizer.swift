//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

enum FallbackSanitizer {

    private static let regexPattern = "^[0-9]+[.a-zA-Z0-9_-]*$|^[a-zA-Z]+[a-zA-Z0-9_-]*$"
    private static let regex = try? NSRegularExpression(pattern: regexPattern)

    enum DiscardReason {
        case flagName
        case treatment

        func message() -> String {
            switch self {
                case .flagName:
                    "Invalid flag name (max 100 chars, no spaces)"
                case .treatment:
                    "Invalid treatment (max 100 chars and comply with \(regexPattern))"
            }
        }
    }

    // MARK: - Global
    static func sanitize(treatment: FallbackTreatment) -> FallbackTreatment? {
        if !isValidTreatment(treatment) {
            Logger.e("Fallback treatments - Discarded fallback: \(DiscardReason.treatment.message())")
            return nil
        }
        return treatment
    }

    // MARK: - By Flag
    static func sanitize(byFlagFallbacks: [String: FallbackTreatment]) -> [String: FallbackTreatment] {
        var sanitized: [String: FallbackTreatment] = [:]

        for (flag, treatment) in byFlagFallbacks {
            guard isValidFlagName(flag) else {
                Logger.e("Fallback treatments - Discarded flag '\(flag)': \(DiscardReason.flagName.message())")
                continue
            }
            guard isValidTreatment(treatment) else {
                Logger.e("Fallback treatments - Discarded treatment for flag '\(flag)': \(DiscardReason.treatment.message())")
                continue
            }
            sanitized[flag] = treatment
        }
        return sanitized
    }

    private static func isValidFlagName(_ name: String) -> Bool {
        name.count <= 100 && !name.contains(" ")
    }

    private static func isValidTreatment(_ fallback: FallbackTreatment) -> Bool {
        if fallback.treatment.count > 100 {
            return false
        }

        let range = NSRange(fallback.treatment.startIndex..<fallback.treatment.endIndex, in: fallback.treatment)
        return regex?.firstMatch(in: fallback.treatment, range: range)?.range == range
    }
}
