import Foundation
import Logging

public final class DefaultSplitFactoryBuilder: SplitFactoryBuilder {

    private var apiKey: String = ""
    private var target: Target?
    private var evaluationFilters: EvaluationFilters?

    public init() {}

    @discardableResult
    public func setApiKey(_ apiKey: String) -> SplitFactoryBuilder {
        self.apiKey = apiKey
        return self
    }

    @discardableResult
    public func setTarget(_ target: Target) -> SplitFactoryBuilder {
        self.target = target
        return self
    }

    @discardableResult
    public func setEvaluationFilters(_ filters: EvaluationFilters) -> SplitFactoryBuilder {
        self.evaluationFilters = filters
        return self
    }

    public func build() -> SplitFactory? {
        guard !apiKey.isEmpty else {
            Logger.e("API key must not be empty")
            return nil
        }

        guard let target = target else {
            Logger.e("Target is required to build SplitFactory")
            return nil
        }

        guard !target.matchingKey.isEmpty else {
            Logger.e("Target matching key must not be empty")
            return nil
        }

        return DefaultSplitFactory(
            apiKey: apiKey,
            target: target,
            evaluationFilters: evaluationFilters
        )
    }
}
