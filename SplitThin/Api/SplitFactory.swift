//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging
import Tracker

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
    private let authProvider: AuthProvider
    private let evaluationRepository: EvaluationRepository
    private let fetchCoordinator: EvaluationFetchCoordinator
    private let streaming: Streaming
    private let observer: Observer // For factory lifecycle logging & telemetry
    private let evaluationStorage: EvaluationReadStorage
    private let coreDataStorage: CoreDataStorage
    private let telemetryStorage: TelemetryReadStorage & TelemetryWriteStorage

    private var splitManager: DefaultSplitManager?
    private var clients = [Key: SplitClient]()
    private var syncManagers = [Key: SyncManager]()
    private var isDestroyed = false

    private var pushDisabled = false
    private let fallbackLock = NSLock()

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

    init(sdkKey: SdkKey, target: Target, config: SplitClientConfig, evaluationFilters: EvaluationFilters?, secureHttpClient: SecureHttpClient, authProvider: AuthProvider, evaluationRepository: EvaluationRepository, fetchCoordinator: EvaluationFetchCoordinator, streaming: Streaming, evaluationStorage: EvaluationReadStorage, coreDataStorage: CoreDataStorage, splitManager: DefaultSplitManager, factoryObserver: Observer, telemetryStorage: TelemetryReadStorage & TelemetryWriteStorage) {
        self.sdkKey = sdkKey
        self.defaultTarget = target
        self.defaultKey = target.key
        self.config = config
        self.evaluationFilters = evaluationFilters
        self.secureHttpClient = secureHttpClient
        self.authProvider = authProvider
        self.evaluationRepository = evaluationRepository
        self.fetchCoordinator = fetchCoordinator
        self.streaming = streaming
        self.evaluationStorage = evaluationStorage
        self.coreDataStorage = coreDataStorage
        self.splitManager = splitManager
        self.observer = factoryObserver
        self.telemetryStorage = telemetryStorage

        splitManager.activeTargetsProvider = { [weak self] in
            guard let self else { return [] }
            return self.clients.values.map { $0.target }
        }

        // Streaming is factory-wide; when the server disables push, every client must fall back to polling.
        streaming.setPushDisabledHandler { [weak self] in
            self?.fallbackAllToPolling()
        }

        observer.notify(event: .factoryInitStarted)
        createClient(target: target)
        observer.notify(event: .factoryInitCompleted)
    }

    public func getClient(_ target: Target? = nil) -> SplitClient {
        let resolvedTarget = target ?? defaultTarget

        if let existing = clients[resolvedTarget.key] {
            if existing.target != resolvedTarget {
                Task { [weak existing] in existing?.setTarget(target: resolvedTarget) }
            }
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

        authProvider.register(target: target.matchingKey)

        // 1. Wire up the per-client components

            // Events
            let eventDispatcher = EventDispatcher() // CompositeObserver in the spec
            let eventsManager = DefaultSplitEventsManager(config: config)
            eventDispatcher.register(eventsManager)
            eventDispatcher.register(LoggingObserver())

            // Telemetry
            let telemetryObserver = TelemetryObserver(storage: telemetryStorage, sessionId: UUID().uuidString, config: config)
            eventDispatcher.register(telemetryObserver)
            let telemetrySubmitter = DefaultTelemetrySubmitter(storage: telemetryStorage, secureHttpClient: secureHttpClient, activeSessionId: telemetryObserver.sessionId)

            // Sync
            let periodicScheduler = DefaultEvaluationPeriodicScheduler(fetchCoordinator: fetchCoordinator, evaluationRepository: evaluationRepository, observer: eventDispatcher, target: target, filters: evaluationFilters, intervalSeconds: config.pollingRate)
            let syncManager = DefaultSyncManager(syncMode: config.syncMode, evaluationRepository: evaluationRepository, observer: eventDispatcher, evaluationStorage: evaluationStorage, eventsManager: eventsManager, periodicScheduler: periodicScheduler, streaming: streaming, target: target)
            let fallbackCalculator = DefaultFallbackTreatmentsCalculator(fallbacksConfig: config.fallbackTreatments)
            let treatmentsManager = DefaultTreatmentsManager(target: target, evaluationRepository: evaluationRepository, fallbackCalculator: fallbackCalculator)
            
            // Tracking
            let eventsStorage = DefaultEventsStorage(storage: coreDataStorage)
            let eventSerializer = DefaultEventSerializer()
            let eventsSubmitter = DefaultHttpEventsSubmitter(secureHttpClient: secureHttpClient)
            let eventTask = DefaultEventTask(storage: eventsStorage, serializer: eventSerializer, submitter: eventsSubmitter, observer: eventDispatcher, target: target)
            let submissionCoordinator = DefaultEventSubmissionCoordinator(eventTask: eventTask, observer: eventDispatcher)
            let eventsTracker = DefaultEventsTracker(storage: eventsStorage, coordinator: submissionCoordinator, observer: eventDispatcher)
            let eventsScheduler = DefaultEventsPeriodicScheduler(coordinator: submissionCoordinator, intervalSeconds: config.pushRate)
            let tracker = DefaultTracker(defaultTrafficType: target.trafficType, initialEventSizeInBytes: 1024, eventValidator: ThinEventValidator(), propertyValidator: ThinPropertyValidator(), logger: ThinTrackerLogger(), onEventPush: { trackerEvent in
                guard !trackerEvent.trafficType.isEmpty else {
                    Logger.e("Tracker event not tracked because trafficType is empty")
                    return
                }
                
                let event = EventEntity(key: trackerEvent.key ?? "", trafficType: trackerEvent.trafficType, eventType: trackerEvent.eventType, value: trackerEvent.value, properties: trackerEvent.properties, timestamp: Date(timeIntervalSince1970: Double(trackerEvent.timestamp ?? 0) / 1000.0))
                Task { await eventsTracker.track(event) }
            })

        // 2. Create
        let client = DefaultSplitClient(target: target, treatmentsManager: treatmentsManager, eventsManager: eventsManager, authProvider: authProvider, observer: eventDispatcher, syncManager: syncManager, tracker: tracker, eventsTracker: eventsTracker, eventsScheduler: eventsScheduler, telemetryObserver: telemetryObserver, telemetrySubmitter: telemetrySubmitter, fetchCoordinator: fetchCoordinator, evaluationRepository: evaluationRepository)

        // 3. Register
        clients[target.key] = client
        withLock(fallbackLock) { syncManagers[target.key] = syncManager }

        // 4. Start
        eventsManager.start()
        syncManager.start()
        eventsScheduler.start()

        // If push was already disabled by the server, this client must poll instead of stream.
        let alreadyPushDisabled = withLock(fallbackLock) { pushDisabled }
        if alreadyPushDisabled {
            syncManager.fallbackToPolling()
        }

        observer.notify(event: .clientCreated)

        return client
    }

    private func fallbackAllToPolling() {
        let managers: [SyncManager] = withLock(fallbackLock) {
            pushDisabled = true
            return Array(syncManagers.values)
        }
        Logger.d("SplitFactory: push disabled by server, falling back to polling for \(managers.count) client(s)")
        managers.forEach { $0.fallbackToPolling() }
    }
}
