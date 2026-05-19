//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging
import Http
import BackoffCounter

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
    var connectionFactory: ((EvaluationFetchCoordinator) -> Streaming)?
    var observer: Observer?

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

        let resolvedObserver = buildObserver()
        let (secureHttp, builtAuthProvider) = buildSecureHttpClientAndAuth(serviceEndpoints: serviceEndpoints, sdkKey: sdkKey.sdkKey, observer: resolvedObserver)
        let evaluationProvider = DefaultEvaluationProvider(secureHttpClient: secureHttp)

        let databaseName = Self.databaseName(prefix: config.prefix, apiKey: sdkKey.sdkKey)
        let coreDataStorage = CoreDataStorage(databaseName: databaseName)
        let evaluationStorage = PersistentStorage(storage: coreDataStorage)

        let fetchCoordinator = DefaultEvaluationFetchCoordinator(provider: evaluationProvider, observer: resolvedObserver, storage: evaluationStorage)
        let evaluationRepository = DefaultEvaluationRepository(fetchCoordinator: fetchCoordinator, evaluationFilters: evaluationFilters)
        let splitManager = DefaultSplitManager(evaluationRepository: evaluationRepository, target: target)

        // Streaming
        let streaming: Streaming
        if let streamingFactory = connectionFactory {
            streaming = streamingFactory(fetchCoordinator)  // Just for testing
        } else {
            streaming = DefaultStreaming(target: target, 
                                         authProvider: builtAuthProvider, 
                                         streamingEndpoint: serviceEndpoints.streamingServiceEndpoint, 
                                         httpClient: httpClient ?? DefaultHttpClient.shared, 
                                         fetchCoordinator: fetchCoordinator, 
                                         notificationParser: DefaultThinNotificationParser(), 
                                         jwtParser: DefaultSseJwtParser(), 
                                         backoffCounter: DefaultBackoffCounter(backoffBase: 1))
        }

        let telemetryStorage = DefaultTelemetryStorage(storage: coreDataStorage)

        return DefaultSplitFactory(sdkKey: sdkKey, target: target, config: config, evaluationFilters: evaluationFilters, secureHttpClient: secureHttp, evaluationRepository: evaluationRepository, fetchCoordinator: fetchCoordinator, streaming: streaming, evaluationStorage: evaluationStorage, coreDataStorage: coreDataStorage, splitManager: splitManager, factoryObserver: resolvedObserver, telemetryStorage: telemetryStorage)
    }

    private func configureLogger() {
        if let loggerLevel = Logging.LogLevel(rawValue: config.logLevel.rawValue) {
            Logger.shared.level = loggerLevel
        }
    }

    private func buildSecureHttpClientAndAuth(serviceEndpoints: ServiceEndpoints, sdkKey: String, observer: Observer) -> (SecureHttpClient, AuthProvider) {
        let http = httpClient ?? DefaultHttpClient.shared
        let retryable = retryableHttpClient ?? DefaultRetryableHttpClient(httpClient: http, observer: observer)
        let storage = DefaultCredentialStorage()
        let fetcher = DefaultCredentialFetcher(retryableHttpClient: retryable, observer: observer, authEndpoint: serviceEndpoints.authServiceEndpoint, sdkKey: sdkKey, configsEnabled: config.dynamicConfig)
        let auth = authProvider ?? DefaultAuthProvider(credentialStorage: storage, credentialFetcher: fetcher, observer: observer)
        let client = secureHttpClient ?? DefaultSecureHttpClient(retryableHttpClient: retryable, authProvider: auth, serviceEndpoints: serviceEndpoints, configsEnabled: config.dynamicConfig, apiKey: sdkKey)
        return (client, auth)
    }

    // Observer override access point. JUST for testing
    private func buildObserver() -> Observer {
        if let observer = observer {
            return observer
        }

        // Production. Default.
        let dispatcher = EventDispatcher()
        dispatcher.register(LoggingObserver())
        return dispatcher
    }

    private static let kDbMagicCharsCount = 4

    static func databaseName(prefix: String?, apiKey: String) -> String {
        let keyFragment: String
        if apiKey.count >= kDbMagicCharsCount * 2 {
            keyFragment = "\(apiKey.prefix(kDbMagicCharsCount))\(apiKey.suffix(kDbMagicCharsCount))"
        } else {
            keyFragment = apiKey
        }
        if let prefix {
            return "split_\(prefix)_\(keyFragment)"
        }
        return "split_\(keyFragment)"
    }
}
