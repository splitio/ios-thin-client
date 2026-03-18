import Foundation

public protocol SplitClient: AnyObject {

    /// Current target for this client.
    var target: Target { get }

    // MARK: - Evaluation
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult
    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]

    // MARK: - Target switching
    func setTarget(target: Target) async

    // MARK: - Events
    func addEventListener(listener: SplitEventListener)

    // MARK: - Track
    func track(eventType: String, value: Double?, properties: EventProperties?)

    // MARK: - Lifecycle
    func destroy() async
    func flush() async
}
