import Foundation

protocol EvaluationReadStorage: Sendable {
    func get(flag: String, target: Target) async -> EvaluationResult?
    func get(flags: [String], target: Target) async -> [EvaluationResult]
    func get(byFlagSets flagSets: [String], target: Target) async -> [EvaluationResult]
    func getFlagNames(target: Target) async -> [String]
    func lastChangeNumber(target: Target) async -> Int64?
}
