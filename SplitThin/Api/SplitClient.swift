//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging
import Tracker

public protocol SplitClient: AnyObject {
    var target: Target { get }
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) -> EvaluationResult
    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult]
    func setTarget(target: Target)
    func addEventListener(_ listener: SplitEventListener)
    func removeEventListener(_ listener: SplitEventListener)
    @discardableResult
    func track(eventType: String, value: Double?, properties: EventProperties?) -> Bool
    func destroy() async
    func flush() async
}

final class DefaultSplitClient: SplitClient {

    private(set) var target: Target
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
    private var clientListeners = [SplitEventListener]()
    private var isDestroyed = false

    init(target: Target, treatmentsManager: TreatmentsManager, eventsManager: SplitEventsManager, authProvider: AuthProvider, observer: Observer, syncManager: SyncManager, tracker: Tracker, eventsTracker: EventsTracker, eventsScheduler: EventsPeriodicScheduler, telemetryObserver: TelemetryObserver, telemetrySubmitter: TelemetrySubmitter, fetchCoordinator: EvaluationFetchCoordinator) {
        self.target = target
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
    }

    // MARK: - Evaluations

    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) -> EvaluationResult {
        observer.notify(event: .evaluationRequested(flagName: flag, target: target))
        return treatmentsManager.getTreatment(flag: flag, evaluationOptions: evaluationOptions)
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult] {
        treatmentsManager.getTreatments(flags: flags, evaluationOptions: evaluationOptions)
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult] {
        treatmentsManager.getTreatmentsByFlagSets(flagSets: flagSets, evaluationOptions: evaluationOptions)
    }

    // MARK: - Target switching
    func setTarget(target: Target) {
        observer.notify(event: .targetSwitchStarted)
        let previousTarget = self.target
        self.target = target

        if previousTarget.matchingKey != target.matchingKey {
            // Register the new key to get a valid auth token for it.
            authProvider.unregister(target: previousTarget.matchingKey)
            authProvider.register(target: target.matchingKey)

            // Stop refetching/bitmap-checking the old key on the factory-wide coordinator.
            fetchCoordinator.unregister(target: previousTarget)
        }

        syncManager.setTarget(target)
        treatmentsManager.setTarget(target)
        observer.notify(event: .targetSwitchCompleted)
    }

    // MARK: - Events

    func addEventListener(_ listener: SplitEventListener) {
        clientListeners.append(listener) // We are saving them here to know which ones to remove from the EventsManager when the client is
                                         // destroyed, since EventsManager does not keep a registry of listeners by client.
        eventsManager.addListener(listener)
    }

    func removeEventListener(_ listener: SplitEventListener) {
        // Comparing memory addresses to find the exact EventListener on local array (not just one that has the same content)
        clientListeners.removeElementByMemoryAddress(listener)
        eventsManager.removeListener(listener)
    }

    // MARK: - Tracking

    @discardableResult
    func track(eventType: String, value: Double?, properties: EventProperties?) -> Bool {
        guard !isDestroyed else {
            observer.notify(event: .trackDropped(reason: .destroyed))
            return false
        }

        observer.notify(event: .trackCalled)
        return tracker.track(eventType: eventType, trafficType: target.trafficType, value: value, properties: properties, matchingKey: target.matchingKey, isSdkReady: true)
    }

    // MARK: - Lifecycle

    func destroy() async {
        guard !isDestroyed else { return }
        observer.notify(event: .destroyStarted)
        isDestroyed = true

        authProvider.unregister(target: target.matchingKey)

        eventsScheduler.stop()
        await eventsTracker.flush()

        await telemetryObserver.persistNow()
        await telemetrySubmitter.flush(count: nil)

        for listener in clientListeners {
            eventsManager.removeListener(listener)
        }
        clientListeners.removeAll()

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

// MARK: - API variations
public extension SplitClient {
    func getTreatment(flag: String) -> EvaluationResult {
        getTreatment(flag: flag, evaluationOptions: nil)
    }

    func getTreatments(flags: [String]) -> [EvaluationResult] {
        getTreatments(flags: flags, evaluationOptions: nil)
    }

    func getTreatmentsByFlagSets(flagSets: [String]) -> [EvaluationResult] {
        getTreatmentsByFlagSets(flagSets: flagSets, evaluationOptions: nil)
    }
}
