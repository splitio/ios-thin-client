import Foundation

public protocol SplitClient: AnyObject {
    var target: Target { get }
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult
    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]
    func setTarget(target: Target) async
    func addEventListener(listener: SplitEventListener)
    func track(eventType: String, value: Double?, properties: EventProperties?)
    func destroy() async
    func flush() async
}

final class DefaultSplitClient: SplitClient {

    private(set) var target: Target
    private let treatmentsManager: TreatmentsManager
    private var isDestroyed = false
    private var listeners = [SplitEventListener]()

    init(target: Target, treatmentsManager: TreatmentsManager) {
        self.target = target
        self.treatmentsManager = treatmentsManager
    }

    // MARK: - Evaluation
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult {
        await treatmentsManager.getTreatment(flag: flag, evaluationOptions: evaluationOptions)
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        await treatmentsManager.getTreatments(flags: flags, evaluationOptions: evaluationOptions)
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        await treatmentsManager.getTreatmentsByFlagSets(flagSets: flagSets, evaluationOptions: evaluationOptions)
    }

    // MARK: - Target switching
    func setTarget(target: Target) async {
        self.target = target
    }

    // MARK: - Events
    func addEventListener(listener: SplitEventListener) {
        listeners.append(listener)
    }

    // MARK: - Track
    func track(eventType: String, value: Double?, properties: EventProperties?) {
        // TODO: Connect with tracker module
    }

    // MARK: - Lifecycle
    func destroy() async {
        guard !isDestroyed else { return }
        isDestroyed = true
        listeners.removeAll()
    }

    func flush() async {}
}
