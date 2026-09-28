//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

/// Configuration for rollout cache validity (persisted evaluations).
///
/// Controls how long cached evaluations remain valid and whether the cache
/// should be cleared on SDK initialization. Consumed at factory build time.
public struct RolloutCacheConfiguration: Sendable {

    static let defaultExpirationDays = 10
    static let minExpirationDays = 1

    let expirationDays: Int
    let clearOnInit: Bool

    private init(expirationDays: Int, clearOnInit: Bool) {
        self.expirationDays = expirationDays
        self.clearOnInit = clearOnInit
    }

    /// Creates a new builder for `RolloutCacheConfiguration`.
    public static func builder() -> Builder {
        Builder()
    }

    /// Builder for creating `RolloutCacheConfiguration` instances.
    public final class Builder {

        private var expirationDays = RolloutCacheConfiguration.defaultExpirationDays
        private var clearOnInit = false

        /// Sets the expiration time for the rollout cache, in days. Default is 10.
        /// Values below 1 fall back to the default.
        @discardableResult
        public func set(expirationDays: Int) -> Builder {
            if expirationDays < RolloutCacheConfiguration.minExpirationDays {
                Logger.w("Cache expiration must be at least \(RolloutCacheConfiguration.minExpirationDays) day. Using default value.")
                self.expirationDays = RolloutCacheConfiguration.defaultExpirationDays
            } else {
                self.expirationDays = expirationDays
            }
            return self
        }

        /// Sets whether the rollout cache should be cleared on initialization. Default is false.
        @discardableResult
        public func set(clearOnInit: Bool) -> Builder {
            self.clearOnInit = clearOnInit
            return self
        }

        /// Builds the `RolloutCacheConfiguration` with the configured values.
        public func build() -> RolloutCacheConfiguration {
            RolloutCacheConfiguration(expirationDays: expirationDays, clearOnInit: clearOnInit)
        }
    }
}
