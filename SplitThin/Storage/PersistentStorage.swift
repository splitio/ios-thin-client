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
    private let cacheValidator: CacheValidator

    init(storage: CoreDataStorage, cacheValidator: CacheValidator) {
        self.storage = storage
        self.cacheValidator = cacheValidator
    }

    // MARK: - EvaluationWriteStorage

    func upsert(change: EvaluationChange) async throws {
        let matchingKey = change.target.matchingKey
        let bucketingKey = change.target.bucketingKey

        try await storage.upsertClientSession(
            matchingKey: matchingKey,
            bucketingKey: bucketingKey,
            attributesHash: cacheValidator.fingerprint(for: change.target),
            attributes: change.target.attributes,
            changeNumber: change.changeNumber
        )

        let evaluations = change.evaluations.map { eval in
            (flagName: eval.flag, treatment: eval.treatment, config: eval.config, sets: eval.flagSets, changeNumber: eval.changeNumber)
        }
        try await storage.upsertEvaluations(matchingKey: matchingKey, bucketingKey: bucketingKey, evaluations: evaluations)
    }

    func clear(target: Target) async {
        try? await storage.deleteClientSession(matchingKey: target.matchingKey, bucketingKey: target.bucketingKey)
    }

    // MARK: - EvaluationReadStorage

    func get(target: Target, flag: String) async -> EvaluationResult? {
        guard let eval = await storage.getEvaluation(matchingKey: target.matchingKey, bucketingKey: target.bucketingKey, flagName: flag) else {
            return nil
        }
        return EvaluationResult(flag: flag, treatment: eval.treatment, changeNumber: eval.changeNumber, flagSets: eval.sets ?? [], config: eval.config)
    }

    func get(target: Target, flags: [String]) async -> [EvaluationResult] {
        let evaluations = await storage.getEvaluations(matchingKey: target.matchingKey, bucketingKey: target.bucketingKey, flagNames: flags)
        return evaluations.map { eval in
            EvaluationResult(flag: eval.flagName, treatment: eval.treatment, changeNumber: eval.changeNumber, flagSets: eval.sets ?? [], config: eval.config)
        }
    }

    func get(target: Target, byFlagSets flagSets: [String]) async -> [EvaluationResult] {
        let allEvaluations = await storage.getAllEvaluations(matchingKey: target.matchingKey, bucketingKey: target.bucketingKey)
        let requestedSets = Set(flagSets)

        return allEvaluations.compactMap { eval in
            guard let sets = eval.sets, !Set(sets).isDisjoint(with: requestedSets) else {
                return nil
            }
            return EvaluationResult(flag: eval.flagName, treatment: eval.treatment, changeNumber: eval.changeNumber, flagSets: sets, config: eval.config)
        }
    }

    func getAll(target: Target) async -> [EvaluationResult] {
        let evaluations = await storage.getAllEvaluations(matchingKey: target.matchingKey, bucketingKey: target.bucketingKey)
        let flagNames = evaluations.map { $0.flagName }.joined(separator: ", ")
        Logger.d("PersistentStorage: Loaded \(evaluations.count) flags for '\(target.matchingKey)': [\(flagNames)]")
        return evaluations.map { eval in
            EvaluationResult(flag: eval.flagName, treatment: eval.treatment, changeNumber: eval.changeNumber, flagSets: eval.sets ?? [], config: eval.config)
        }
    }

    func getFlagNames(target: Target) async -> [String] {
        await storage.getFlagNames(matchingKey: target.matchingKey, bucketingKey: target.bucketingKey)
    }

    func lastChangeNumber(target: Target) async -> Int64? {
        let storedCache = await storage.getAttributesHash(matchingKey: target.matchingKey, bucketingKey: target.bucketingKey)
        guard cacheValidator.isValid(storedAttrHash: storedCache, for: target) else {
            return nil
        }
        return await storage.getChangeNumber(matchingKey: target.matchingKey, bucketingKey: target.bucketingKey)
    }
}
