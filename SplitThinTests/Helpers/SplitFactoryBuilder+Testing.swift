import Foundation
import Http
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

    @discardableResult
    func setCredentialStorage(_ storage: CredentialStorage) -> DefaultSplitFactoryBuilder {
        self.credentialStorage = storage
        return self
    }

    @discardableResult
    func setStreamingConnectionManagerFactory(_ factory: @escaping (EvaluationFetchCoordinator) -> Streaming) -> DefaultSplitFactoryBuilder {
        self.connectionFactory = factory
        return self
    }

    @discardableResult
    func setFactoryObserver(_ observer: Observer) -> DefaultSplitFactoryBuilder {
        self.observer = observer
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
    @discardableResult
    func getClient(_ matchingKey: String, trafficType: String = "user") -> SplitClient {
        getClient(Target(matchingKey: matchingKey, trafficType: trafficType))
    }
}

extension SplitClient {
    @discardableResult
    func getTreatment(_ flag: String) -> EvaluationResult {
        getTreatment(flag: flag)
    }
}

extension CredentialFetcher {
    @discardableResult
    func fetchCredential(for user: String) async throws -> JwtCredential {
        try await fetchCredential(for: [user])
    }
}

extension SecureHttpClient {
    @discardableResult
    func fetchEvaluations(target: Target) async throws -> HttpResponse {
        try await fetchEvaluations(target: target, filters: nil)
    }
}

extension RetryableHttpClient {
    @discardableResult
    func execute(_ endpoint: Endpoint, category: RequestCategory) async throws -> HttpResponse {
        try await execute(endpoint, category: category, body: nil)
    }
}

extension SplitFactoryBuilder {
    @discardableResult
    func setTarget(_ matchingKey: String, trafficType: String = "user") -> SplitFactoryBuilder {
        setTarget(Target(matchingKey: matchingKey, trafficType: trafficType))
    }

    @discardableResult
    func setSdkKey(_ key: String) -> SplitFactoryBuilder {
        setSdkKey(SdkKey(key))
    }
}