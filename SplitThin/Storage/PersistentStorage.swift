//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol EvaluationReadStorage: Sendable {
    func get(target: Target, flag: String) async -> EvaluationResult?
    func get(target: Target, flags: [String]) async -> [EvaluationResult]
    func get(target: Target, byFlagSets flagSets: [String]) async -> [EvaluationResult]
    func getAll(target: Target) async -> [EvaluationResult]
    func getFlagNames(target: Target) async -> [String]
    func lastChangeNumber(target: Target) async -> Int64?
}

protocol EvaluationWriteStorage: Sendable {
    func upsert(change: EvaluationChange) async throws
    func clear(target: Target) async
}

final class PersistentStorage: EvaluationReadStorage, EvaluationWriteStorage, Sendable {

    private let storage: CoreDataStorage

    init(storage: CoreDataStorage) {
        self.storage = storage
    }

    // MARK: - EvaluationWriteStorage

    func upsert(change: EvaluationChange) async throws {
        let matchingKey = change.target.matchingKey

        try await storage.upsertClientSession(
            matchingKey: matchingKey,
            attributes: change.target.attributes,
            changeNumber: change.changeNumber
        )

        let evaluations = change.evaluations.map { eval in
            (flagName: eval.flag, treatment: eval.treatment, config: eval.config, sets: eval.flagSets)
        }
        try await storage.upsertEvaluations(matchingKey: matchingKey, evaluations: evaluations)
    }

    func clear(target: Target) async {
        try? await storage.deleteClientSession(matchingKey: target.matchingKey)
    }

    // MARK: - EvaluationReadStorage

    func get(target: Target, flag: String) async -> EvaluationResult? {
        guard let eval = await storage.getEvaluation(matchingKey: target.matchingKey, flagName: flag) else {
            return nil
        }
        return EvaluationResult(flag: flag, treatment: eval.treatment, flagSets: eval.sets ?? [], config: eval.config)
    }

    func get(target: Target, flags: [String]) async -> [EvaluationResult] {
        let evaluations = await storage.getEvaluations(matchingKey: target.matchingKey, flagNames: flags)
        return evaluations.map { eval in
            EvaluationResult(flag: eval.flagName, treatment: eval.treatment, flagSets: eval.sets ?? [], config: eval.config)
        }
    }

    func get(target: Target, byFlagSets flagSets: [String]) async -> [EvaluationResult] {
        let allEvaluations = await storage.getAllEvaluations(matchingKey: target.matchingKey)
        let requestedSets = Set(flagSets)

        return allEvaluations.compactMap { eval in
            guard let sets = eval.sets, !Set(sets).isDisjoint(with: requestedSets) else {
                return nil
            }
            return EvaluationResult(flag: eval.flagName, treatment: eval.treatment, flagSets: sets, config: eval.config)
        }
    }

    func getAll(target: Target) async -> [EvaluationResult] {
        let evaluations = await storage.getAllEvaluations(matchingKey: target.matchingKey)
        let flagNames = evaluations.map { $0.flagName }.joined(separator: ", ")
        Logger.d("PersistentStorage: Loaded \(evaluations.count) flags for '\(target.matchingKey)': [\(flagNames)]")
        return evaluations.map { eval in
            EvaluationResult(flag: eval.flagName, treatment: eval.treatment, flagSets: eval.sets ?? [], config: eval.config)
        }
    }

    func getFlagNames(target: Target) async -> [String] {
        await storage.getFlagNames(matchingKey: target.matchingKey)
    }

    func lastChangeNumber(target: Target) async -> Int64? {
        await storage.getChangeNumber(matchingKey: target.matchingKey)
    }
}
