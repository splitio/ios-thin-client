import Foundation
import Logging
import Http

public protocol SplitFactoryBuilder {
    @discardableResult
    func setSdkKey(_ sdkKey: SdkKey) -> SplitFactoryBuilder
    @discardableResult
    func setTarget(_ target: Target) -> SplitFactoryBuilder
    @discardableResult
    func setConfig(_ config: SplitClientConfig) -> SplitFactoryBuilder
    @discardableResult
    func setEvaluationFilters(_ filters: EvaluationFilters) -> SplitFactoryBuilder
    func build() -> SplitFactory?
}

public final class DefaultSplitFactoryBuilder: NSObject, SplitFactoryBuilder {

    private var sdkKey: SdkKey?
    private var target: Target?
    private var config = SplitClientConfig.builder().build()
    private var evaluationFilters: EvaluationFilters?
    private var httpClient: HttpClient?
    private var authProvider: AuthProvider?

    // Internals for testing
    var secureHttpClient: SecureHttpClient?
    var retryableHttpClient: RetryableHttpClient?

    public override init() {
        super.init()
    }

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
    public func setConfig(_ config: SplitClientConfig) -> SplitFactoryBuilder {
        self.config = config
        return self
    }

    @discardableResult
    public func setEvaluationFilters(_ filters: EvaluationFilters) -> SplitFactoryBuilder {
        self.evaluationFilters = filters
        return self
    }

    public func build() -> SplitFactory? {
        configureLogger()

        guard let sdkKey = sdkKey, !sdkKey.sdkKey.isEmpty else {
            Logger.e("SDK key must not be empty")
            return nil
        }

        guard let target = target else {
            Logger.e("Target is required to build SplitFactory")
            return nil
        }

        guard !target.key.matchingKey.isEmpty else {
            Logger.e("Target matching key must not be empty")
            return nil
        }

        let serviceEndpoints = config.serviceEndpoints ?? ServiceEndpoints.builder().build()

        if !serviceEndpoints.allEndpointsValid {
            Logger.e("Could not create the factory, there are invalid endpoints")
            if let message = serviceEndpoints.endpointsInvalidMessage {
                Logger.e(message)
            }
            return nil
        }

        let factoryObserver = EventDispatcher()
        factoryObserver.register(LoggingObserver())

        let secureHttp = secureHttpClient ?? buildSecureHttpClient(serviceEndpoints: serviceEndpoints, sdkKey: sdkKey.sdkKey, observer: factoryObserver)
        let evaluationProvider = DefaultEvaluationProvider(secureHttpClient: secureHttp)
        let fetchCoordinator = DefaultEvaluationFetchCoordinator(provider: evaluationProvider, observer: factoryObserver)
        let evaluationRepository = DefaultEvaluationRepository(fetchCoordinator: fetchCoordinator, evaluationFilters: evaluationFilters)
        let splitManager = DefaultSplitManager(evaluationRepository: evaluationRepository, target: target)

        return DefaultSplitFactory(sdkKey: sdkKey, target: target, config: config, evaluationFilters: evaluationFilters, secureHttpClient: secureHttp, evaluationRepository: evaluationRepository, fetchCoordinator: fetchCoordinator, splitManager: splitManager, factoryObserver: factoryObserver)
    }

    private func configureLogger() {
        if let loggerLevel = Logging.LogLevel(rawValue: config.logLevel.rawValue) {
            Logger.shared.level = loggerLevel
        }
    }

    private func buildSecureHttpClient(serviceEndpoints: ServiceEndpoints, sdkKey: String, observer: Observer) -> SecureHttpClient {
        let http = httpClient ?? DefaultHttpClient.shared
        let retryable = retryableHttpClient ?? DefaultRetryableHttpClient(httpClient: http, observer: observer)
        let storage = DefaultCredentialStorage()
        let fetcher = DefaultCredentialFetcher(retryableHttpClient: retryable, observer: observer, authEndpoint: serviceEndpoints.authServiceEndpoint, sdkKey: sdkKey)
        let auth = authProvider ?? DefaultAuthProvider(credentialStorage: storage, credentialFetcher: fetcher, observer: observer)
        return DefaultSecureHttpClient(retryableHttpClient: retryable, authProvider: auth, serviceEndpoints: serviceEndpoints)
    }
}
