//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

/// Returned when factory initialization fails, to avoid crashing the host app.
final class FailedClient: SplitClient, Sendable {

    var target: Target {
        Target(matchingKey: "", trafficType: "")
    }

    func getTreatment(flag: String) -> EvaluationResult {
        EvaluationResult(flag: flag, treatment: "control", flagSets: [])
    }

    func getTreatments(flags: [String]) -> [EvaluationResult] {
        flags.map { EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
    }

    func getTreatmentsByFlagSets(flagSets: [String]) -> [EvaluationResult] {
        []
    }

    func setTarget(target: Target) {}

    func addEventListener(_ listener: SplitEventListener) {}

    func removeEventListener(_ listener: SplitEventListener) {}

    @discardableResult
    func track(eventType: String, value: Double?, properties: EventProperties?) -> Bool { false }

    func destroy() async {}

    func flush() async {}
}
