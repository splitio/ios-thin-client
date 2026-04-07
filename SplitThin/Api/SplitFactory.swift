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
    private let evaluationRepository: EvaluationRepository
    private let eventsManager: SplitEventsManager
    private let syncManager: SyncManager

    private var splitManager: DefaultSplitManager?
    private var clients = [Key: SplitClient]()
    private var isDestroyed = false

    public var client: SplitClient {
        clients[defaultKey] ?? FailedClient()
    }

    public var version: String {
        Version.sdk
    }

    init(sdkKey: SdkKey, target: Target, config: SplitClientConfig, evaluationFilters: EvaluationFilters?, secureHttpClient: SecureHttpClient, evaluationRepository: EvaluationRepository, eventsManager: SplitEventsManager, syncManager: SyncManager, splitManager: DefaultSplitManager) {
        self.sdkKey = sdkKey
        self.defaultTarget = target
        self.defaultKey = target.key
        self.config = config
        self.evaluationFilters = evaluationFilters
        self.secureHttpClient = secureHttpClient
        self.evaluationRepository = evaluationRepository
        self.eventsManager = eventsManager
        self.syncManager = syncManager
        self.splitManager = splitManager

        let treatmentsManager = DefaultTreatmentsManager(target: target, evaluationRepository: evaluationRepository)
        let client = DefaultSplitClient(target: target, treatmentsManager: treatmentsManager, eventsManager: eventsManager)
        clients[target.key] = client

        Task {
            await syncManager.start()
        }
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

        let treatmentsManager = DefaultTreatmentsManager(target: resolvedTarget, evaluationRepository: evaluationRepository)
        let newClient = DefaultSplitClient(target: resolvedTarget, treatmentsManager: treatmentsManager, eventsManager: eventsManager)
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

        await syncManager.stop()

        for client in clients.values {
            await client.destroy()
        }
        
        clients.removeAll()
        splitManager = nil
    }
}
