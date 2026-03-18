import Foundation
import Logging

public protocol SplitFactory {
    var client: SplitClient { get }
    func getClient(_ target: Target?) -> SplitClient
    func manager() -> SplitManager
    func destroy() async
}

public final class DefaultSplitFactory: SplitFactory, @unchecked Sendable {

    private static let initErrorMessage =
        "Something happened on Split init and the client couldn't be created"

    private let sdkKey: SdkKey
    private let defaultTarget: Target
    private let defaultKey: Key
    private let config: SplitClientConfig
    private let evaluationFilters: EvaluationFilters?
    private let secureHttpClient: SecureHttpClient

    private var splitManager: DefaultSplitManager?
    private var clients = [Key: SplitClient]()
    private var isDestroyed = false

    public var client: SplitClient {
        clients[defaultKey] ?? FailedClient()
    }

    public var version: String {
        Version.sdk
    }

    init(sdkKey: SdkKey, target: Target, config: SplitClientConfig, evaluationFilters: EvaluationFilters?, secureHttpClient: SecureHttpClient) {
        self.sdkKey = sdkKey
        self.defaultTarget = target
        self.defaultKey = target.key
        self.config = config
        self.evaluationFilters = evaluationFilters
        self.secureHttpClient = secureHttpClient

        let manager = DefaultSplitManager()
        splitManager = manager
        let treatmentsManager = DefaultTreatmentsManager(target: target, secureHttpClient: secureHttpClient, splitManager: manager)
        let client = DefaultSplitClient(target: target, treatmentsManager: treatmentsManager)
        clients[target.key] = client
    }

    public func getClient(_ target: Target? = nil) -> SplitClient {
        let resolvedTarget = target ?? defaultTarget

        if let existing = clients[resolvedTarget.key] {
            return existing
        }

        if isDestroyed {
            Logger.e(Self.initErrorMessage)
            return FailedClient()
        }

        let treatmentsManager = DefaultTreatmentsManager(target: resolvedTarget, secureHttpClient: secureHttpClient, splitManager: splitManager)
        let newClient = DefaultSplitClient(target: resolvedTarget, treatmentsManager: treatmentsManager)
        clients[resolvedTarget.key] = newClient
        return newClient
    }

    public func manager() -> SplitManager {
        if let manager = splitManager {
            return manager
        }
        Logger.e(Self.initErrorMessage)
        return FailedManager()
    }

    public func destroy() async {
        guard !isDestroyed else { return }
        isDestroyed = true

        for client in clients.values {
            await client.destroy()
        }
        
        clients.removeAll()
        splitManager = nil
    }
}
