import Foundation
@testable import SplitThin

final class EvaluationRepositoryMock: EvaluationRepository, @unchecked Sendable {

    var getTreatmentCalls = [String]()
    var getTreatmentsCalls = [[String]]()
    var getTreatmentsByFlagSetsCalls = [[String]]()
    var setTargetCalls = [Target]()

    var treatmentToReturn: EvaluationResult?
    var treatmentsToReturn = [EvaluationResult]()

    func getTreatment(flag: String, target: Target) async -> EvaluationResult? {
        getTreatmentCalls.append(flag)
        return treatmentToReturn
    }

    func getTreatments(flags: [String], target: Target) async -> [EvaluationResult] {
        getTreatmentsCalls.append(flags)
        return treatmentsToReturn
    }

    func getTreatmentsByFlagSets(_ flagSets: [String], target: Target) async -> [EvaluationResult] {
        getTreatmentsByFlagSetsCalls.append(flagSets)
        return treatmentsToReturn
    }

    func getFlagNames(target: Target) async -> [String] {
        []
    }

    func setTarget(_ target: Target) async {
        setTargetCalls.append(target)
    }

    func initialize(target: Target) async {
        setTargetCalls.append(target)
    }
}
