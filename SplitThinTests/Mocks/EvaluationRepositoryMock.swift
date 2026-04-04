import Foundation
@testable import SplitThin

final class EvaluationRepositoryMock: EvaluationRepository, @unchecked Sendable {

    var getEvaluationCalls = [String]()
    var getEvaluationsCalls = [[String]]()
    var getEvaluationsByFlagSetsCalls = [[String]]()
    var setTargetCalls = [Target]()

    var storedEvaluationToReturn: StoredEvaluation?
    var storedEvaluationsToReturn = [StoredEvaluation]()

    func getEvaluation(flag: String, target: Target) -> StoredEvaluation? {
        getEvaluationCalls.append(flag)
        return storedEvaluationToReturn
    }

    func getEvaluations(flags: [String], target: Target) -> [StoredEvaluation] {
        getEvaluationsCalls.append(flags)
        return storedEvaluationsToReturn
    }

    func getEvaluationsByFlagSets(_ flagSets: [String], target: Target) -> [StoredEvaluation] {
        getEvaluationsByFlagSetsCalls.append(flagSets)
        return storedEvaluationsToReturn
    }

    func getFlagNames(target: Target) -> [String] {
        []
    }

    func setTarget(_ target: Target) {
        setTargetCalls.append(target)
    }

    func initialize(target: Target) async {
        setTargetCalls.append(target)
    }
}
