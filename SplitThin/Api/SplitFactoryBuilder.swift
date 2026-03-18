import Foundation

/// Builder protocol for constructing a SplitFactory.
public protocol SplitFactoryBuilder {

    /// Sets the SDK key.
    @discardableResult
    func setSdkKey(_ sdkKey: SdkKey) -> SplitFactoryBuilder

    /// Sets the default target (equivalent to Key in the full SDK).
    @discardableResult
    func setTarget(_ target: Target) -> SplitFactoryBuilder

    /// Sets the SDK configuration.
    @discardableResult
    func setConfig(_ config: SplitClientConfig) -> SplitFactoryBuilder

    /// Sets evaluation filters to control which flags are fetched.
    @discardableResult
    func setEvaluationFilters(_ filters: EvaluationFilters) -> SplitFactoryBuilder

    /// Builds the factory. Returns nil if required parameters are missing or invalid.
    func build() -> SplitFactory?
}
