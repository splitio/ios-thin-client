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
    private let fetchCoordinator: EvaluationFetchCoordinator

    private var splitManager: DefaultSplitManager?
    private var clients = [Key: SplitClient]()
    private var syncManagers = [Key: SyncManager]()
    private var isDestroyed = false

    public var client: SplitClient {
        clients[defaultKey] ?? FailedClient()
    }

    public var version: String {
        Version.sdk
    }

    init(sdkKey: SdkKey, target: Target, config: SplitClientConfig, evaluationFilters: EvaluationFilters?, secureHttpClient: SecureHttpClient, evaluationRepository: EvaluationRepository, fetchCoordinator: EvaluationFetchCoordinator, splitManager: DefaultSplitManager) {
        self.sdkKey = sdkKey
        self.defaultTarget = target
        self.defaultKey = target.key
        self.config = config
        self.evaluationFilters = evaluationFilters
        self.secureHttpClient = secureHttpClient
        self.evaluationRepository = evaluationRepository
        self.fetchCoordinator = fetchCoordinator
        self.splitManager = splitManager

        createClient(target: target)
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

        return createClient(target: resolvedTarget)
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

        for syncManager in syncManagers.values {
            await syncManager.stop()
        }
        syncManagers.removeAll()

        for client in clients.values {
            await client.destroy()
        }
        clients.removeAll()

        splitManager = nil
    }

    // MARK: - Private

    @discardableResult
    private func createClient(target: Target) -> SplitClient {
        let eventsManager = DefaultSplitEventsManager(config: config)
        let periodicScheduler = DefaultEvaluationPeriodicScheduler(fetchCoordinator: fetchCoordinator, eventsManager: eventsManager, target: target, filters: evaluationFilters, intervalSeconds: config.evaluationRefreshRate)
        let streaming = DefaultStreaming(fetchCoordinator: fetchCoordinator, eventsManager: eventsManager, secureHttpClient: secureHttpClient, target: target)
        let syncManager = DefaultSyncManager(syncMode: config.syncMode, evaluationRepository: evaluationRepository, eventsManager: eventsManager, periodicScheduler: periodicScheduler, streaming: streaming, target: target)

        let treatmentsManager = DefaultTreatmentsManager(target: target, evaluationRepository: evaluationRepository)
        let client = DefaultSplitClient(target: target, treatmentsManager: treatmentsManager, eventsManager: eventsManager)

        clients[target.key] = client
        syncManagers[target.key] = syncManager

        Task {
            await syncManager.start()
        }

        return client
    }
}
