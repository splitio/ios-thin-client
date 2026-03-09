import Foundation
import Logging

public final class DefaultSplitFactoryBuilder: SplitFactoryBuilder {

    private var sdkKey: SdkKey?
    private var target: Target?
    private var evaluationFilters: EvaluationFilters?

    public init() {}

    @discardableResult
    public func setSdkKey(_ sdkKey: SdkKey) -> SplitFactoryBuilder {
        self.sdkKey = sdkKey
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
        guard let sdkKey = sdkKey, !sdkKey.sdkKey.isEmpty else {
            Logger.e("SDK key must not be empty")
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
            sdkKey: sdkKey,
            target: target,
            evaluationFilters: evaluationFilters
        )
    }
}
