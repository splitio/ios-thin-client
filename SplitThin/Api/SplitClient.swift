//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

public protocol SplitClient: AnyObject {
    var target: Target { get }
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) -> EvaluationResult
    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult]
    func setTarget(target: Target)
    func addEventListener(_ listener: SplitEventListener)
    func removeEventListener(_ listener: SplitEventListener)
    func track(eventType: String, value: Double?, properties: EventProperties?)
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
    private var clientListeners = [SplitEventListener]()
    private var isDestroyed = false

    init(target: Target, treatmentsManager: TreatmentsManager, eventsManager: SplitEventsManager, authProvider: AuthProvider, observer: Observer, syncManager: SyncManager) {
        self.target = target
        self.treatmentsManager = treatmentsManager
        self.eventsManager = eventsManager
        self.authProvider = authProvider
        self.observer = observer
        self.syncManager = syncManager
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
        self.target = target
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

    func track(eventType: String, value: Double?, properties: EventProperties?) {
        guard !isDestroyed else {
            observer.notify(event: .trackDropped(reason: .destroyed))
            return
        }
        observer.notify(event: .trackCalled)
        // TODO: Connect with tracker module
    }

    // MARK: - Lifecycle

    func destroy() async {
        guard !isDestroyed else { return }
        observer.notify(event: .destroyStarted)
        isDestroyed = true

        authProvider.unregister(target: target.matchingKey)

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
        // TODO: Connect with flush module
        observer.notify(event: .flushCompleted(.events))
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
