import Foundation
@testable import SplitThin

final class EvaluationRepositoryMock: EvaluationRepository, @unchecked Sendable {

    var getTreatmentCalls = [String]()
    var getTreatmentsCalls = [[String]]()
    var getTreatmentsByFlagSetsCalls = [[String]]()
    var setTargetCalls = [Target]()
    var updateCalls = [[EvaluationResult]]()
    var clearCallCount = 0

    var treatmentToReturn: EvaluationResult?
    var treatmentsToReturn = [EvaluationResult]()

    func getTreatment(flag: String) -> EvaluationResult? {
        getTreatmentCalls.append(flag)
        return treatmentToReturn
    }

    func getTreatments(flags: [String]) -> [EvaluationResult] {
        getTreatmentsCalls.append(flags)
        return treatmentsToReturn
    }

    func getTreatmentsByFlagSets(_ flagSets: [String]) -> [EvaluationResult] {
        getTreatmentsByFlagSetsCalls.append(flagSets)
        return treatmentsToReturn
    }

    func getFlagNames() -> [String] {
        []
    }

    func setTarget(_ target: Target) {
        setTargetCalls.append(target)
    }

    func update(_ evaluations: [EvaluationResult]) {
        updateCalls.append(evaluations)
    }

    func clear() {
        clearCallCount += 1
    }
}
