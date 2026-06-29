//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging
import Tracker

public protocol SplitClient: AnyObject, Sendable {
    var target: Target { get }
    func getTreatment(flag: String) -> EvaluationResult
    func getTreatments(flags: [String]) -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String]) -> [EvaluationResult]
    func setTarget(target: Target)
    func addEventListener(_ listener: SplitEventListener)
    func removeEventListener(_ listener: SplitEventListener)
    @discardableResult
    func track(eventType: String, value: Double?, properties: EventProperties?) -> Bool
    func destroy() async
    func flush() async
}

final class DefaultSplitClient: SplitClient, @unchecked Sendable {

    private let lock = NSLock() // protects (`_target`, `clientListeners`, `isDestroyed`)
    private let setTargetQueue = DispatchQueue(label: "split-client-set-target")
    private var _target: Target
    var target: Target { withLock(lock) { _target } }

    private let treatmentsManager: TreatmentsManager
    private let eventsManager: SplitEventsManager
    private let authProvider: AuthProvider
    private let observer: Observer // For SDK events & logging
    private let syncManager: SyncManager
    private let tracker: Tracker
    private let eventsTracker: EventsTracker
    private let eventsScheduler: EventsPeriodicScheduler
    private let telemetryObserver: TelemetryObserver
    private let telemetrySubmitter: TelemetrySubmitter
    private let fetchCoordinator: EvaluationFetchCoordinator
    private let evaluationRepository: EvaluationRepository
    private var clientListeners = [SplitEventListener]()
    private var isDestroyed = false

    init(target: Target, treatmentsManager: TreatmentsManager, eventsManager: SplitEventsManager, authProvider: AuthProvider, observer: Observer, syncManager: SyncManager, tracker: Tracker, eventsTracker: EventsTracker, eventsScheduler: EventsPeriodicScheduler, telemetryObserver: TelemetryObserver, telemetrySubmitter: TelemetrySubmitter, fetchCoordinator: EvaluationFetchCoordinator, evaluationRepository: EvaluationRepository) {
        self._target = target
        self.treatmentsManager = treatmentsManager
        self.eventsManager = eventsManager
        self.authProvider = authProvider
        self.observer = observer
        self.syncManager = syncManager
        self.tracker = tracker
        self.eventsTracker = eventsTracker
        self.eventsScheduler = eventsScheduler
        self.telemetryObserver = telemetryObserver
        self.telemetrySubmitter = telemetrySubmitter
        self.fetchCoordinator = fetchCoordinator
        self.evaluationRepository = evaluationRepository

        registerUpdateAction(for: target)
    }

    // MARK: - Evaluations

    func getTreatment(flag: String) -> EvaluationResult {
        let currentTarget = withLock(lock) { _target }
        observer.notify(event: .evaluationRequested(flagName: flag, target: currentTarget))
        return treatmentsManager.getTreatment(flag: flag)
    }

    func getTreatments(flags: [String]) -> [EvaluationResult] {
        treatmentsManager.getTreatments(flags: flags)
    }

    func getTreatmentsByFlagSets(flagSets: [String]) -> [EvaluationResult] {
        treatmentsManager.getTreatmentsByFlagSets(flagSets: flagSets)
    }

    // MARK: - Target switching

    func setTarget(target: Target) {
        setTargetQueue.async { [weak self] in
            self?.applyTargetSwitch(to: target)
        }
    }

    private func applyTargetSwitch(to target: Target) {
        observer.notify(event: .targetSwitchStarted)

        let previousTarget = withLock(lock) { () -> Target in
            let previous = _target
            _target = target
            return previous
        }

        if previousTarget.matchingKey != target.matchingKey {
            // Register the new key to get a valid auth token for it.
            authProvider.unregister(target: previousTarget.matchingKey)
            authProvider.register(target: target.matchingKey)

            // Stop refetching/bitmap-checking the old key on the factory-wide coordinator.
            fetchCoordinator.unregister(target: previousTarget)
            registerUpdateAction(for: target)
        }

        syncManager.setTarget(target)
        treatmentsManager.setTarget(target)

        observer.notify(event: .targetSwitchCompleted)
    }

    private func registerUpdateAction(for target: Target) {
        fetchCoordinator.registerOnUpdateAction(for: target.key) { [weak self, target] fetchResult in
            guard let self else { return }
            let changedFlags = self.evaluationRepository.applyFetched(fetchResult, for: target)
            self.observer.notify(event: .evaluationsUpdated(SdkUpdateMetadata(type: .flagsUpdate, names: changedFlags, changeNumber: fetchResult.changeNumber)))
        }
    }

    // MARK: - Events

    func addEventListener(_ listener: SplitEventListener) {
        // We are saving them here to know which ones to remove from the EventsManager when the client is
        // destroyed, since EventsManager does not keep a registry of listeners by client.
        withLock(lock) { clientListeners.append(listener) }
        eventsManager.addListener(listener)
    }

    func removeEventListener(_ listener: SplitEventListener) {
        // Comparing memory addresses to find the exact EventListener on local array (not just one that has the same content)
        withLock(lock) { clientListeners.removeElementByMemoryAddress(listener) }
        eventsManager.removeListener(listener)
    }

    // MARK: - Tracking

    @discardableResult
    func track(eventType: String, value: Double? = nil, properties: EventProperties? = nil) -> Bool {
        let (destroyed, currentTarget) = withLock(lock) { (isDestroyed, _target) }
        guard !destroyed else {
            observer.notify(event: .trackDropped(reason: .destroyed))
            return false
        }

        observer.notify(event: .trackCalled)
        return tracker.track(eventType: eventType, trafficType: currentTarget.trafficType, value: value, properties: properties, matchingKey: currentTarget.matchingKey, isSdkReady: true)
    }

    // MARK: - Lifecycle

    func destroy() async {
        let alreadyDestroyed = withLock(lock) { () -> Bool in
            if isDestroyed { return true }
            isDestroyed = true
            return false
        }
        guard !alreadyDestroyed else { return }

        observer.notify(event: .destroyStarted)

        let currentTarget = withLock(lock) { _target }
        authProvider.unregister(target: currentTarget.matchingKey)

        eventsScheduler.stop()
        await eventsTracker.flush()

        await telemetryObserver.persistNow()
        await telemetrySubmitter.flush(count: nil)

        let listeners = withLock(lock) { () -> [SplitEventListener] in
            let snapshot = clientListeners
            clientListeners.removeAll()
            return snapshot
        }
        for listener in listeners {
            eventsManager.removeListener(listener)
        }

        eventsManager.stop()
        await syncManager.stop()
        observer.notify(event: .destroyCompleted)
    }

    func flush() async {
        observer.notify(event: .flushStarted(.events))
        await eventsTracker.flush()
        observer.notify(event: .flushCompleted(.events))

        observer.notify(event: .flushStarted(.telemetry))
        await telemetrySubmitter.flush(count: nil)
        observer.notify(event: .flushCompleted(.telemetry))
    }
}