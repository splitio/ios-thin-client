import Foundation
@testable import SplitThin

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
