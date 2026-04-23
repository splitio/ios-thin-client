import Foundation
@testable import SplitThin

final class EvaluationStorageMock: EvaluationReadStorage, @unchecked Sendable {

    var evaluationsToReturn: [EvaluationResult] = []
    var flagNamesToReturn: [String] = []
    var changeNumberToReturn: Int64?

    var getCallCount = 0
    var getAllCallCount = 0
    var getFlagNamesCallCount = 0
    var lastChangeNumberCallCount = 0

    func get(target: Target, flag: String) async -> EvaluationResult? {
        getCallCount += 1
        return evaluationsToReturn.first { $0.flag == flag }
    }

    func get(target: Target, flags: [String]) async -> [EvaluationResult] {
        getCallCount += 1
        return evaluationsToReturn.filter { flags.contains($0.flag) }
    }

    func get(target: Target, byFlagSets flagSets: [String]) async -> [EvaluationResult] {
        getCallCount += 1
        let requestedSets = Set(flagSets)
        return evaluationsToReturn.filter { eval in
            !Set(eval.flagSets).isDisjoint(with: requestedSets)
        }
    }

    func getAll(target: Target) async -> [EvaluationResult] {
        getAllCallCount += 1
        return evaluationsToReturn
    }

    func getFlagNames(target: Target) async -> [String] {
        getFlagNamesCallCount += 1
        return flagNamesToReturn
    }

    func lastChangeNumber(target: Target) async -> Int64? {
        lastChangeNumberCallCount += 1
        return changeNumberToReturn
    }

    func reset() {
        evaluationsToReturn = []
        flagNamesToReturn = []
        changeNumberToReturn = nil
        getCallCount = 0
        getAllCallCount = 0
        getFlagNamesCallCount = 0
        lastChangeNumberCallCount = 0
    }
}
