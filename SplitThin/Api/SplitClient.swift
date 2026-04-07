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
    private var clientListeners = [SplitEventListener]()
    private var isDestroyed = false

    init(target: Target, treatmentsManager: TreatmentsManager, eventsManager: SplitEventsManager) {
        self.target = target
        self.treatmentsManager = treatmentsManager
        self.eventsManager = eventsManager
    }

    // MARK: - Evaluation
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) -> EvaluationResult {
        treatmentsManager.getTreatment(flag: flag, evaluationOptions: evaluationOptions)
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult] {
        treatmentsManager.getTreatments(flags: flags, evaluationOptions: evaluationOptions)
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) -> [EvaluationResult] {
        treatmentsManager.getTreatmentsByFlagSets(flagSets: flagSets, evaluationOptions: evaluationOptions)
    }

    // MARK: - Target switching
    func setTarget(target: Target) {
        self.target = target
        treatmentsManager.setTarget(target)
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

    // MARK: - Track
    func track(eventType: String, value: Double?, properties: EventProperties?) {
        // TODO: Connect with tracker module
    }

    // MARK: - Lifecycle
    func destroy() async {
        guard !isDestroyed else { return }
        isDestroyed = true

        for listener in clientListeners {
            eventsManager.removeListener(listener)
        }
        clientListeners.removeAll()
    }

    func flush() async {}
}

// MARK: - Evaluations API variations
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
