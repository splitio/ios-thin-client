import Foundation
@testable import SplitThin

final class EvaluationRepositoryMock: EvaluationRepository, @unchecked Sendable {

    var getEvaluationCalls = [String]()
    var getEvaluationsCalls = [[String]]()
    var getEvaluationsByFlagSetsCalls = [[String]]()
    var setTargetCalls = [Target]()
    var initializeErrorToThrow: Error?

    var evaluationToReturn: StoredEvaluation?
    var evaluationsToReturn = [StoredEvaluation]()

    func getEvaluation(flag: String, target: Target) -> StoredEvaluation? {
        getEvaluationCalls.append(flag)
        return evaluationToReturn
    }

    func getEvaluations(flags: [String], target: Target) -> [StoredEvaluation] {
        getEvaluationsCalls.append(flags)
        return evaluationsToReturn
    }

    func getEvaluationsByFlagSets(_ flagSets: [String], target: Target) -> [StoredEvaluation] {
        getEvaluationsByFlagSetsCalls.append(flagSets)
        return evaluationsToReturn
    }

    func getFlagNames(target: Target) -> [String] {
        []
    }

    func setTarget(_ target: Target) {
        setTargetCalls.append(target)
    }

    func initialize(target: Target) async throws {
        setTargetCalls.append(target)
        if let error = initializeErrorToThrow {
            throw error
        }
    }

}
