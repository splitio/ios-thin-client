import Foundation
@testable import SplitThin

// This file centralizes all internal methods used to inject components in the 
// SDK creation process, for testing purposes.
// Here you will find extensions of many creational components. Break down when file gets too big.

extension DefaultSplitFactoryBuilder {
    @discardableResult
    func setSecureHttpClient(_ client: SecureHttpClient) -> DefaultSplitFactoryBuilder {
        self.secureHttpClient = client
        return self
    }
    
    @discardableResult
    func setRetryableHttpClient(_ client: RetryableHttpClient) -> DefaultSplitFactoryBuilder {
        self.retryableHttpClient = client
        return self
    }
}

extension SplitConfigBuilder {
    @discardableResult
    func setMinEvaluationRefreshRate(_ value: Int) -> SplitConfigBuilder {
        self.minEvaluationRefreshRateOverride = value
        return self
    }
}

extension SplitFactory {
    func getClient(_ matchingKey: String) -> SplitClient {
        getClient(Target(matchingKey: matchingKey))
    }
}

extension SplitClient {
    func getTreatment(_ flag: String) -> EvaluationResult {
        getTreatment(flag: flag)
    }
}

extension SplitFactoryBuilder {
    @discardableResult
    func setTarget(_ matchingKey: String) -> SplitFactoryBuilder {
        setTarget(Target(matchingKey: matchingKey))
    }

    @discardableResult
    func setSdkKey(_ key: String) -> SplitFactoryBuilder {
        setSdkKey(SdkKey(key))
    }
}
