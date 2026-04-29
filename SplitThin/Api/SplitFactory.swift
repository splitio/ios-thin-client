//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

public protocol SplitFactory {
    var client: SplitClient { get }
    func getClient(_ target: Target?) -> SplitClient
    func manager() -> SplitManager
    func destroy() async
}

public final class DefaultSplitFactory: SplitFactory, @unchecked Sendable {

    private let sdkKey: SdkKey
    private let defaultTarget: Target
    private let defaultKey: Key
    private let config: SplitClientConfig
    private let evaluationFilters: EvaluationFilters?
    private let secureHttpClient: SecureHttpClient
    private let evaluationRepository: EvaluationRepository
    private let fetchCoordinator: EvaluationFetchCoordinator
    private let streamingManager: StreamingManager
    private let observer: Observer // For factory lifecycle logging & telemetry
    private let evaluationStorage: EvaluationReadStorage
    private let coreDataStorage: CoreDataStorage

    private var splitManager: DefaultSplitManager?
    private var clients = [Key: SplitClient]()
    private var syncManagers = [Key: SyncManager]()
    private var isDestroyed = false

    private static let initErrorMessage = "Something happened on Split init and the client couldn't be created"

    public var client: SplitClient {
        clients[defaultKey] ?? FailedClient()
    }

    public var version: String {
        Version.sdk
    }

    var syncManager: SyncManager? {
        syncManagers[defaultKey]
    }

    init(sdkKey: SdkKey, target: Target, config: SplitClientConfig, evaluationFilters: EvaluationFilters?, secureHttpClient: SecureHttpClient, evaluationRepository: EvaluationRepository, fetchCoordinator: EvaluationFetchCoordinator, streamingManager: StreamingManager, evaluationStorage: EvaluationReadStorage, coreDataStorage: CoreDataStorage, splitManager: DefaultSplitManager, factoryObserver: Observer) {
        self.sdkKey = sdkKey
        self.defaultTarget = target
        self.defaultKey = target.key
        self.config = config
        self.evaluationFilters = evaluationFilters
        self.secureHttpClient = secureHttpClient
        self.evaluationRepository = evaluationRepository
        self.fetchCoordinator = fetchCoordinator
        self.streamingManager = streamingManager
        self.evaluationStorage = evaluationStorage
        self.coreDataStorage = coreDataStorage
        self.splitManager = splitManager
        self.observer = factoryObserver

        observer.notify(event: .factoryInitStarted)
        createClient(target: target)
        observer.notify(event: .factoryInitCompleted)
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
        observer.notify(event: .destroyStarted)
        isDestroyed = true

        for client in clients.values {
            await client.destroy()
        }
        clients.removeAll()
        syncManagers.removeAll()

        splitManager = nil
        observer.notify(event: .destroyCompleted)
    }

    // MARK: - Private

    @discardableResult
    private func createClient(target: Target) -> SplitClient {

        // 1. Wire up just the per-client components
        let eventDispatcher = EventDispatcher() // CompositeObserver in the spec
        let eventsManager = DefaultSplitEventsManager(config: config)
        eventDispatcher.register(eventsManager)
        eventDispatcher.register(LoggingObserver())

        // Connect FetchCoordinator (that is factory wide) with per-client eventsManager to fire updates events
        (fetchCoordinator as? DefaultEvaluationFetchCoordinator)?.registerOnUpdateAction(for: target.key) { [weak eventDispatcher, evaluationRepository, target] fetchResult in
            guard let eventDispatcher else { return }
            evaluationRepository.update(fetchResult.evaluations, for: target)
            eventDispatcher.notify(event: .evaluationsUpdated(SdkUpdateMetadata(type: .flagsUpdate, names: fetchResult.evaluations.map { $0.flag }, changeNumber: fetchResult.changeNumber)))
        }

        let periodicScheduler = DefaultEvaluationPeriodicScheduler(fetchCoordinator: fetchCoordinator, observer: eventDispatcher, target: target, filters: evaluationFilters, intervalSeconds: config.evaluationRefreshRate)
        let streaming = DefaultStreaming(streamingManager: streamingManager)
        let syncManager = DefaultSyncManager(syncMode: config.syncMode, evaluationRepository: evaluationRepository, observer: eventDispatcher, evaluationStorage: evaluationStorage, eventsManager: eventsManager, periodicScheduler: periodicScheduler, streaming: streaming, target: target)
        let fallbackCalculator = DefaultFallbackTreatmentsCalculator(fallbacksConfig: config.fallbackTreatments)
        let treatmentsManager = DefaultTreatmentsManager(target: target, evaluationRepository: evaluationRepository, fallbackCalculator: fallbackCalculator)

        // Tracking stack
        let eventsStorage = DefaultEventsStorage(storage: coreDataStorage)
        let eventsValidator = DefaultEventsValidator()
        let eventSerializer = DefaultEventSerializer()
        let eventsSubmitter = DefaultHttpEventsSubmitter(secureHttpClient: secureHttpClient)
        let eventTask = DefaultEventTask(storage: eventsStorage, serializer: eventSerializer, submitter: eventsSubmitter, observer: eventDispatcher, target: target)
        let submissionCoordinator = DefaultEventSubmissionCoordinator(eventTask: eventTask, observer: eventDispatcher)
        let eventsTracker = DefaultEventsTracker(validator: eventsValidator, storage: eventsStorage, coordinator: submissionCoordinator, observer: eventDispatcher)
        let eventsScheduler = DefaultEventsPeriodicScheduler(coordinator: submissionCoordinator, intervalSeconds: config.pushRate)

        // 2. Create
        let client = DefaultSplitClient(target: target, treatmentsManager: treatmentsManager, eventsManager: eventsManager, observer: eventDispatcher, syncManager: syncManager, eventsTracker: eventsTracker, eventsScheduler: eventsScheduler)

        // 3. Register
        clients[target.key] = client
        syncManagers[target.key] = syncManager

        // 4. Start
        eventsManager.start()
        syncManager.start()
        eventsScheduler.start()

        observer.notify(event: .clientCreated)
        return client
    }
}
