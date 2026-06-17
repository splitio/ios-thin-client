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

    var flagNamesToReturn = [String]()
    var flagNamesByKey = [String: [String]]()
    var updateCalls = [(evaluations: [EvaluationResult], target: Target)]()

    func getFlagNames(target: Target) -> [String] {
        flagNamesByKey[target.matchingKey] ?? flagNamesToReturn
    }

    var changedFlagsToReturn = [String]()

    @discardableResult
    func update(_ evaluations: [EvaluationResult], for target: Target) -> [String] {
        updateCalls.append((evaluations, target))
        return changedFlagsToReturn
    }

    var applyFetchedCalls = [(result: FetchResult, target: Target)]()

    @discardableResult
    func applyFetched(_ result: FetchResult, for target: Target) -> [String] {
        applyFetchedCalls.append((result, target))
        guard result.shouldApplyToCache else { return [] }
        return update(result.evaluations, for: target)
    }

    var loadFromCacheCalls = [(evaluations: [EvaluationResult], target: Target)]()

    @discardableResult
    func loadFromCache(_ evaluations: [EvaluationResult], for target: Target) -> [String] {
        loadFromCacheCalls.append((evaluations, target))
        return changedFlagsToReturn
    }

    func setTarget(_ target: Target) {
        setTargetCalls.append(target)
    }

    var fetchResultToReturn = FetchResult(evaluations: [], changeNumber: nil)

    @discardableResult
    func initialize(target: Target) async throws -> FetchResult {
        setTargetCalls.append(target)
        if let error = initializeErrorToThrow {
            throw error
        }
        return fetchResultToReturn
    }
}
