import Foundation

/// Returned when factory initialization fails, to avoid crashing the host app.
final class FailedClient: SplitClient {

    var target: Target {
        Target(matchingKey: "")
    }

    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult {
        EvaluationResult(flag: flag, treatment: "control", flagSets: [])
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        flags.map { EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        []
    }

    func setTarget(target: Target) async {}

    func addEventListener(listener: SplitEventListener) {}

    func track(eventType: String, value: Double?, properties: EventProperties?) {}

    func destroy() async {}

    func flush() async {}
}
