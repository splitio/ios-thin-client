import Foundation

protocol EvaluationWriteStorage: Sendable {
    func upsert(change: EvaluationChange) async throws
    func clear(target: Target) async
}
