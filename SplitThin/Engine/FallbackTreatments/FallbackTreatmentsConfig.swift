//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

public struct FallbackTreatmentsConfig: Sendable {

    let global: FallbackTreatment?
    let byFlag: [String: FallbackTreatment]

    private init(global: FallbackTreatment? = nil, byFlag: [String: FallbackTreatment] = [:]) {
        self.global = global
        self.byFlag = byFlag
    }

    public static func builder() -> Builder {
        Builder()
    }

    public final class Builder {

        private var global: FallbackTreatment?
        private var byFlag: [String: FallbackTreatment] = [:]

        public func build() -> FallbackTreatmentsConfig {
            FallbackTreatmentsConfig(global: global, byFlag: byFlag)
        }

        // MARK: - Global
        @discardableResult
        public func global(_ treatment: FallbackTreatment) -> Builder {
            guard let sanitized = FallbackSanitizer.sanitize(treatment: treatment) else { return self }

            if global != nil {
                Logger.w("Fallback treatments - You had previously set a global fallback. The new value will replace it")
            }

            global = sanitized
            return self
        }

        @discardableResult
        public func global(_ treatment: String) -> Builder {
            global(FallbackTreatment(treatment: treatment))
        }

        // MARK: - By Flag
        @discardableResult
        public func byFlag(_ byFlagFallbacks: [String: FallbackTreatment]) -> Builder {
            for key in byFlagFallbacks.keys where byFlag.keys.contains(key) {
                Logger.w("Duplicate fallback for flag '\(key)'. Overriding existing value.")
            }

            var merged = byFlag
            for (key, value) in byFlagFallbacks {
                merged[key] = value
            }

            byFlag = FallbackSanitizer.sanitize(byFlagFallbacks: merged)
            return self
        }

        @discardableResult
        public func byFlag(_ byFlagFallbacks: [String: String]) -> Builder {
            byFlag(byFlagFallbacks.mapValues { FallbackTreatment(treatment: $0) })
        }
    }
}
