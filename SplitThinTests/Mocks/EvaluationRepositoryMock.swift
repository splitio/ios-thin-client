import Foundation
@testable import SplitThin

final class EvaluationRepositoryMock: EvaluationRepository, @unchecked Sendable {

    var getTreatmentCalls = [(flag: String, target: Target)]()
    var getTreatmentsCalls = [(flags: [String], target: Target)]()
    var getTreatmentsByFlagSetsCalls = [(flagSets: [String], target: Target)]()
    var setTargetCalls = [Target]()
    var updateCalls = [[EvaluationResult]]()
    var clearCallCount = 0

    var treatmentToReturn: EvaluationResult?
    var treatmentsToReturn = [EvaluationResult]()

    func getTreatment(flag: String, target: Target) async -> EvaluationResult? {
        getTreatmentCalls.append((flag, target))
        return treatmentToReturn
    }

    func getTreatments(flags: [String], target: Target) async -> [EvaluationResult] {
        getTreatmentsCalls.append((flags, target))
        return treatmentsToReturn
    }

    func getTreatmentsByFlagSets(_ flagSets: [String], target: Target) async -> [EvaluationResult] {
        getTreatmentsByFlagSetsCalls.append((flagSets, target))
        return treatmentsToReturn
    }

    func getFlagNames(target: Target) async -> [String] {
        []
    }

    func setTarget(_ target: Target) async {
        setTargetCalls.append(target)
    }

    func update(_ evaluations: [EvaluationResult]) {
        updateCalls.append(evaluations)
    }

    func clear() {
        clearCallCount += 1
    }
}
