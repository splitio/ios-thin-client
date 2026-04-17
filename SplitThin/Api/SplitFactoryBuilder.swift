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
    var connectionManagerFactory: ((EvaluationFetchCoordinator) -> StreamingConnectionManager)?

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

        let http = httpClient ?? DefaultHttpClient.shared
        let (secureHttp, builtAuthProvider) = buildSecureHttpClientAndAuth(
            serviceEndpoints: serviceEndpoints, sdkKey: sdkKey.sdkKey, http: http)
        let evaluationProvider = DefaultEvaluationProvider(secureHttpClient: secureHttp)
        let evaluationStorage = InMemoryEvaluationStorage()
        let fetchCoordinator = DefaultEvaluationFetchCoordinator(provider: evaluationProvider, storage: evaluationStorage)
        let evaluationRepository = DefaultEvaluationRepository(fetchCoordinator: fetchCoordinator, storage: evaluationStorage, evaluationFilters: evaluationFilters)
        let splitManager = DefaultSplitManager(evaluationRepository: evaluationRepository, target: target)
        let streamingComponents: StreamingComponents
        if let factory = connectionManagerFactory {
            streamingComponents = StreamingComponents(manager: DefaultStreamingManager(connectionManagerFactory: { factory(fetchCoordinator) }))
        } else {
            streamingComponents = createStreamingComponents(
                target: target,
                authProvider: builtAuthProvider,
                streamingEndpoint: serviceEndpoints.streamingServiceEndpoint,
                httpClient: http,
                fetchCoordinator: fetchCoordinator
            )
        }

        return DefaultSplitFactory(
            sdkKey: sdkKey, target: target, config: config,
            evaluationFilters: evaluationFilters,
            secureHttpClient: secureHttp,
            evaluationRepository: evaluationRepository,
            fetchCoordinator: fetchCoordinator,
            streamingManager: streamingComponents.manager,
            splitManager: splitManager
        )
    }

    private func configureLogger() {
        if let loggerLevel = Logging.LogLevel(rawValue: config.logLevel.rawValue) {
            Logger.shared.level = loggerLevel
        }
    }

    private func buildSecureHttpClientAndAuth(serviceEndpoints: ServiceEndpoints, sdkKey: String, http: HttpClient) -> (SecureHttpClient, AuthProvider) {
        let retryable = retryableHttpClient ?? DefaultRetryableHttpClient(httpClient: http)
        let storage = DefaultCredentialStorage()
        let fetcher = DefaultCredentialFetcher(retryableHttpClient: retryable, authEndpoint: serviceEndpoints.authServiceEndpoint, sdkKey: sdkKey)
        let auth = authProvider ?? DefaultAuthProvider(credentialStorage: storage, credentialFetcher: fetcher)
        let client = secureHttpClient ?? DefaultSecureHttpClient(retryableHttpClient: retryable, authProvider: auth, serviceEndpoints: serviceEndpoints)
        return (client, auth)
    }
}
