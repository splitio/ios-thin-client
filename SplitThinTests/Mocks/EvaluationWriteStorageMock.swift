import Foundation
@testable import SplitThin

final class EvaluationWriteStorageMock: EvaluationWriteStorage, @unchecked Sendable {

    var upsertCalls: [EvaluationChange] = []
    var clearCalls: [Target] = []

    func upsert(change: EvaluationChange) async throws {
        upsertCalls.append(change)
    }

    func clear(target: Target) async {
        clearCalls.append(target)
    }
}
