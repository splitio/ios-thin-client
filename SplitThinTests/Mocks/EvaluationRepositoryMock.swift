import Foundation
@testable import SplitThin

final class EvaluationRepositoryMock: EvaluationRepository, @unchecked Sendable {

    var getEvaluationCalls = [String]()
    var getEvaluationsCalls = [[String]]()
    var getEvaluationsByFlagSetsCalls = [[String]]()
    var setTargetCalls = [Target]()
    var updateCalls = [[EvaluationResult]]()
    var clearCallCount = 0

    var evaluationToReturn: StoredEvaluation?
    var evaluationsToReturn = [StoredEvaluation]()

    func getEvaluation(flag: String) -> StoredEvaluation? {
        getEvaluationCalls.append(flag)
        return evaluationToReturn
    }

    func getEvaluations(flags: [String]) -> [StoredEvaluation] {
        getEvaluationsCalls.append(flags)
        return evaluationsToReturn
    }

    func getEvaluationsByFlagSets(_ flagSets: [String]) -> [StoredEvaluation] {
        getEvaluationsByFlagSetsCalls.append(flagSets)
        return evaluationsToReturn
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
