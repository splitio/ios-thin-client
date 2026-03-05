import Foundation

/// Builder protocol for constructing a SplitFactory.
public protocol SplitFactoryBuilder {

    /// Sets the client API key.
    @discardableResult
    func setApiKey(_ apiKey: String) -> SplitFactoryBuilder

    /// Sets the default target (equivalent to Key in the full SDK).
    @discardableResult
    func setTarget(_ target: Target) -> SplitFactoryBuilder

    /// Sets evaluation filters to control which flags are fetched.
    @discardableResult
    func setEvaluationFilters(_ filters: EvaluationFilters) -> SplitFactoryBuilder

    /// Builds the factory. Returns nil if required parameters are missing or invalid.
    func build() -> SplitFactory?
}
