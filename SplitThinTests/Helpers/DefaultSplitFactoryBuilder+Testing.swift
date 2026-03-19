import Foundation
@testable import SplitThin

extension DefaultSplitFactoryBuilder {
    @discardableResult
    func setSecureHttpClient(_ client: SecureHttpClient) -> DefaultSplitFactoryBuilder {
        self.secureHttpClient = client
        return self
    }
}

extension SplitClientConfig {
    static func setMinEvaluationRefreshRate(_ value: Int) {
        minEvaluationRefreshRate = value
    }
}
