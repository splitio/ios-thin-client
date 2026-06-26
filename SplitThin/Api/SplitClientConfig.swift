//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

/// Configuration options for the Split SDK client.
public struct SplitClientConfig: Sendable {

    static let minEvaluationRefreshRate = 60
    fileprivate static let minTimeout = -1
    fileprivate static let minPushRate = 30
    fileprivate static let prefixPattern = "^[a-zA-Z0-9_]{1,80}$"

    // Compiling here to avoid multiple regex compilations. 
    // This force unwrap is safe, we prefer to crash at compile time if we 
    // have a bad pattern, instead of having the validation silently failing.
    fileprivate static let prefixRegex = try! NSRegularExpression(pattern: prefixPattern)

    let syncMode: SyncMode
    let serviceEndpoints: ServiceEndpoints?
    let impressionsMode: ImpressionsMode
    let configsEnabled: Bool
    let logLevel: LogLevel
    let evaluationsRefreshRate: Int
    let timeout: Int
    let prefix: String?
    let pushRate: Int
    let fallbackTreatments: FallbackTreatmentsConfig
    let evaluationFilters: EvaluationFilters?

    fileprivate init(syncMode: SyncMode, serviceEndpoints: ServiceEndpoints?, impressionsMode: ImpressionsMode, configsEnabled: Bool, logLevel: LogLevel, evaluationRefreshRate: Int, timeout: Int, prefix: String?, pushRate: Int, fallbackTreatments: FallbackTreatmentsConfig, evaluationFilters: EvaluationFilters?) {
        self.syncMode = syncMode
        self.serviceEndpoints = serviceEndpoints
        self.impressionsMode = impressionsMode
        self.configsEnabled = configsEnabled
        self.logLevel = logLevel
        self.evaluationsRefreshRate = evaluationRefreshRate
        self.timeout = timeout
        self.prefix = prefix
        self.pushRate = pushRate
        self.fallbackTreatments = fallbackTreatments
        self.evaluationFilters = evaluationFilters
    }

    /// Creates a new builder for `SplitClientConfig`.
    public static func builder() -> SplitConfigBuilder {
        SplitConfigBuilder()
    }
}

/// Builder for creating `SplitClientConfig` instances.
public final class SplitConfigBuilder {

    private var syncMode: SyncMode = .streaming
    private var serviceEndpoints: ServiceEndpoints?
    private var impressionsMode: ImpressionsMode = .default
    private var configsEnabled: Bool = false
    private var logLevel: LogLevel = .none
    private var evaluationRefreshRate: Int = 3600
    private var timeout: Int = 10
    private var prefix: String?
    private var pushRate: Int = 1800
    private var fallbackTreatments: FallbackTreatmentsConfig = FallbackTreatmentsConfig.builder().build()
    private var evaluationFilters: EvaluationFilters?

    // Internal for testing
    var minEvaluationRefreshRateOverride: Int?

    /// Sets the synchronization mode for fetching feature flag updates.
    /// - `.streaming`: Real-time updates via SSE (default)
    /// - `.polling`: Periodic polling at `evaluationRefreshRate` intervals
    /// - `.singleSync`: Fetch once at startup, no background updates
    @discardableResult
    public func set(syncMode: SyncMode) -> Self {
        self.syncMode = syncMode
        return self
    }

    /// Sets custom endpoints for the SDK services.
    @discardableResult
    public func set(serviceEndpoints: ServiceEndpoints) -> Self {
        self.serviceEndpoints = serviceEndpoints
        return self
    }

    /// Sets how impressions (evaluation events) are recorded and sent.
    /// - `.default`: Standard impression tracking
    /// - `.none`: Disable impression tracking
    @discardableResult
    public func set(impressionsMode: ImpressionsMode) -> Self {
        self.impressionsMode = impressionsMode
        return self
    }

    /// Enables or disables dynamic configuration updates from the server.
    @discardableResult
    public func set(configsEnabled: Bool) -> Self {
        self.configsEnabled = configsEnabled
        return self
    }

    /// Sets the logging verbosity level for SDK internal messages.
    @discardableResult
    public func set(logLevel: LogLevel) -> Self {
        self.logLevel = logLevel
        return self
    }

    /// Sets how often (in seconds) to poll for feature flag updates.
    /// Minimum: 60 seconds. Default: 3600 seconds (1 hour).
    @discardableResult
    public func set(evaluationRefreshRate: Int) -> Self {
        let minRate = minEvaluationRefreshRateOverride ?? SplitClientConfig.minEvaluationRefreshRate
        if evaluationRefreshRate < minRate {
            Logger.w("evaluationRefreshRate must be at least \(minRate) seconds. Using minimum allowed value.")
            self.evaluationRefreshRate = minRate
        } else {
            self.evaluationRefreshRate = evaluationRefreshRate
        }
        return self
    }

    /// Sets the maximum time (in seconds) to wait for the SDK to be ready on startup.
    /// Use `-1` for no timeout (wait indefinitely). Default: -1.
    @discardableResult
    public func set(timeout: Int) -> Self {
        if timeout < SplitClientConfig.minTimeout {
            Logger.w("timeout must be at least \(SplitClientConfig.minTimeout). Using minimum allowed value.")
            self.timeout = SplitClientConfig.minTimeout
        } else {
            self.timeout = timeout
        }
        return self
    }

    /// Sets an optional prefix for storage keys to isolate data between SDK instances.
    /// Must be alphanumeric with underscores, max 80 characters.
    @discardableResult
    public func set(prefix: String?) -> Self {
        if let prefix = prefix {
            let range = NSRange(prefix.startIndex..., in: prefix)
            if SplitClientConfig.prefixRegex.firstMatch(in: prefix, range: range) == nil {
                Logger.w("prefix '\(prefix)' does not match pattern \(SplitClientConfig.prefixPattern). " +
                         "Ignoring value.")
                return self
            }
        }
        self.prefix = prefix
        return self
    }

    /// Sets how often (in seconds) to send recorded impressions and events to the server.
    /// Minimum: 30 seconds. Default: 1800 seconds (30 minutes).
    @discardableResult
    public func set(pushRate: Int) -> Self {
        if pushRate < SplitClientConfig.minPushRate {
            Logger.w("pushRate must be at least \(SplitClientConfig.minPushRate) seconds. " +
                     "Using minimum allowed value.")
            self.pushRate = SplitClientConfig.minPushRate
        } else {
            self.pushRate = pushRate
        }
        return self
    }

    /// Sets the fallback treatments configuration.
    ///
    /// Fallback treatments are used when the SDK would otherwise return `"control"`,
    /// such as when a flag is not found or not yet synced.
    ///
    /// ### Usage Example:
    /// ```swift
    /// let fallbacks = FallbackTreatmentsConfig.builder()
    ///     .global(FallbackTreatment(treatment: "off"))
    ///     .byFlag(["my_flag": FallbackTreatment(treatment: "v2", config: "{\"key\":true}")])
    ///     .build()
    ///
    /// let config = SplitClientConfig.builder()
    ///     .set(fallbackTreatments: fallbacks)
    ///     .build()
    /// ```
    @discardableResult
    public func set(fallbackTreatments: FallbackTreatmentsConfig) -> Self {
        self.fallbackTreatments = fallbackTreatments
        return self
    }

    /// Sets the filters used to narrow the set of feature flags evaluated by the SDK.
    ///
    /// Filters are applied at fetch time so that the SDK only requests the flags
    /// the application cares about, reducing payload size and processing.
    @discardableResult
    public func set(evaluationFilters: EvaluationFilters) -> Self {
        self.evaluationFilters = evaluationFilters
        return self
    }

    /// Builds the `SplitClientConfig` with the configured values.
    public func build() -> SplitClientConfig {
        SplitClientConfig(
            syncMode: syncMode,
            serviceEndpoints: serviceEndpoints,
            impressionsMode: impressionsMode,
            configsEnabled: configsEnabled,
            logLevel: logLevel,
            evaluationRefreshRate: evaluationRefreshRate,
            timeout: timeout,
            prefix: prefix,
            pushRate: pushRate,
            fallbackTreatments: fallbackTreatments,
            evaluationFilters: evaluationFilters
        )
    }
}
