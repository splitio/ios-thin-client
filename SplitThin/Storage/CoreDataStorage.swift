//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import CoreData
import Logging

enum StorageError: Error {
    case entityNotFound
}

final class CoreDataStorage: @unchecked Sendable {

    private static let clientSessionEntity = "ClientSession"
    private static let evaluationEntity = "Evaluation"

    private let container: NSPersistentContainer

    init(databaseName: String) {
        container = NSPersistentContainer(name: databaseName, managedObjectModel: Self.createModel())

        let description = NSPersistentStoreDescription()
        description.url = Self.storeURL(for: databaseName)
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error {
                Logger.e("CoreDataStorage: Failed to load store '\(databaseName)': \(error)")
            }
        }
    }

    // MARK: - ClientSession Operations

    func upsertClientSession(matchingKey: String, attributes: [String: String]?, changeNumber: Int64) async throws {
        try await withContext { context in
            // Delete existing session for this matchingKey (ensures single state per user)
            let deleteRequest = NSFetchRequest<NSManagedObject>(entityName: Self.clientSessionEntity)
            deleteRequest.predicate = NSPredicate(format: "matchingKey == %@", matchingKey)
            for object in try context.fetch(deleteRequest) {
                context.delete(object)
            }

            // Create new session
            guard let entity = NSEntityDescription.entity(forEntityName: Self.clientSessionEntity, in: context) else {
                throw StorageError.entityNotFound
            }
            let session = NSManagedObject(entity: entity, insertInto: context)
            session.setValue(matchingKey, forKey: "matchingKey")
            session.setValue(changeNumber, forKey: "changeNumber")
            session.setValue(self.encodeAttributes(attributes), forKey: "attributes")

            try context.save()
        }
    }

    func getChangeNumber(matchingKey: String) async -> Int64? {
        try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.clientSessionEntity)
            request.predicate = NSPredicate(format: "matchingKey == %@", matchingKey)
            request.fetchLimit = 1
            return try context.fetch(request).first?.value(forKey: "changeNumber") as? Int64
        }
    }

    func deleteClientSession(matchingKey: String) async throws {
        try await withContext { context in
            let sessionRequest = NSFetchRequest<NSManagedObject>(entityName: Self.clientSessionEntity)
            sessionRequest.predicate = NSPredicate(format: "matchingKey == %@", matchingKey)
            for object in try context.fetch(sessionRequest) {
                context.delete(object)
            }

            let evalRequest = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            evalRequest.predicate = NSPredicate(format: "matchingKey == %@", matchingKey)
            for object in try context.fetch(evalRequest) {
                context.delete(object)
            }

            try context.save()
        }
    }

    // MARK: - Evaluation Operations

    func upsertEvaluations(matchingKey: String, evaluations: [(flagName: String, treatment: String, config: String?, sets: [String]?)]) async throws {
        try await withContext { context in
            // Delete all existing evaluations for this matchingKey (ensures single state per user)
            let deleteRequest = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            deleteRequest.predicate = NSPredicate(format: "matchingKey == %@", matchingKey)
            for object in try context.fetch(deleteRequest) {
                context.delete(object)
            }

            // Insert new evaluations
            for eval in evaluations {
                guard let entity = NSEntityDescription.entity(forEntityName: Self.evaluationEntity, in: context) else {
                    throw StorageError.entityNotFound
                }
                let evaluation = NSManagedObject(entity: entity, insertInto: context)
                evaluation.setValue(matchingKey, forKey: "matchingKey")
                evaluation.setValue(eval.flagName, forKey: "flagName")
                evaluation.setValue(eval.treatment, forKey: "treatment")
                evaluation.setValue(eval.config, forKey: "config")
                evaluation.setValue(self.encodeSets(eval.sets), forKey: "sets")
            }

            try context.save()
        }
    }

    func getEvaluation(matchingKey: String, flagName: String) async -> (treatment: String, config: String?, sets: [String]?)? {
        try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            request.predicate = NSPredicate(format: "matchingKey == %@ AND flagName == %@", matchingKey, flagName)
            request.fetchLimit = 1

            guard let result = try context.fetch(request).first else {
                return nil
            }

            let treatment = result.value(forKey: "treatment") as? String ?? "control"
            let config = result.value(forKey: "config") as? String
            let setsJson = result.value(forKey: "sets") as? String
            let sets = self.decodeSets(setsJson)

            return (treatment, config, sets)
        }
    }

    func getEvaluations(matchingKey: String, flagNames: [String]) async -> [(flagName: String, treatment: String, config: String?, sets: [String]?)] {
        guard !flagNames.isEmpty else { return [] }

        return (try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            request.predicate = NSPredicate(format: "matchingKey == %@ AND flagName IN %@", matchingKey, flagNames)

            return try context.fetch(request).map { result in
                let flagName = result.value(forKey: "flagName") as? String ?? ""
                let treatment = result.value(forKey: "treatment") as? String ?? "control"
                let config = result.value(forKey: "config") as? String
                let setsJson = result.value(forKey: "sets") as? String
                let sets = self.decodeSets(setsJson)
                return (flagName, treatment, config, sets)
            }
        }) ?? []
    }

    func getAllEvaluations(matchingKey: String) async -> [(flagName: String, treatment: String, config: String?, sets: [String]?)] {
        (try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            request.predicate = NSPredicate(format: "matchingKey == %@", matchingKey)

            return try context.fetch(request).map { result in
                let flagName = result.value(forKey: "flagName") as? String ?? ""
                let treatment = result.value(forKey: "treatment") as? String ?? "control"
                let config = result.value(forKey: "config") as? String
                let setsJson = result.value(forKey: "sets") as? String
                let sets = self.decodeSets(setsJson)
                return (flagName, treatment, config, sets)
            }
        }) ?? []
    }

    func getFlagNames(matchingKey: String) async -> [String] {
        (try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            request.predicate = NSPredicate(format: "matchingKey == %@", matchingKey)
            request.propertiesToFetch = ["flagName"]

            return try context.fetch(request).compactMap { $0.value(forKey: "flagName") as? String }
        }) ?? []
    }

    // MARK: - Private Helpers

    private func encodeAttributes(_ attributes: [String: String]?) -> String? {
        guard let attributes, !attributes.isEmpty else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: attributes),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func encodeSets(_ sets: [String]?) -> String? {
        guard let sets, !sets.isEmpty else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: sets),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private func decodeSets(_ json: String?) -> [String]? {
        guard let json, let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return nil
        }
        return array
    }

    private func withContext<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let context = container.newBackgroundContext()
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    continuation.resume(returning: try block(context))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Model Definition

    private static func createModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // ClientSession entity
        let clientSessionEntity = NSEntityDescription()
        clientSessionEntity.name = Self.clientSessionEntity
        clientSessionEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let matchingKeyAttr = NSAttributeDescription()
        matchingKeyAttr.name = "matchingKey"
        matchingKeyAttr.attributeType = .stringAttributeType

        let attributesAttr = NSAttributeDescription()
        attributesAttr.name = "attributes"
        attributesAttr.attributeType = .stringAttributeType
        attributesAttr.isOptional = true

        let changeNumberAttr = NSAttributeDescription()
        changeNumberAttr.name = "changeNumber"
        changeNumberAttr.attributeType = .integer64AttributeType

        clientSessionEntity.properties = [matchingKeyAttr, attributesAttr, changeNumberAttr]

        // Evaluation entity
        let evaluationEntity = NSEntityDescription()
        evaluationEntity.name = Self.evaluationEntity
        evaluationEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let evalMatchingKeyAttr = NSAttributeDescription()
        evalMatchingKeyAttr.name = "matchingKey"
        evalMatchingKeyAttr.attributeType = .stringAttributeType

        let flagNameAttr = NSAttributeDescription()
        flagNameAttr.name = "flagName"
        flagNameAttr.attributeType = .stringAttributeType

        let treatmentAttr = NSAttributeDescription()
        treatmentAttr.name = "treatment"
        treatmentAttr.attributeType = .stringAttributeType

        let configAttr = NSAttributeDescription()
        configAttr.name = "config"
        configAttr.attributeType = .stringAttributeType
        configAttr.isOptional = true

        let setsAttr = NSAttributeDescription()
        setsAttr.name = "sets"
        setsAttr.attributeType = .stringAttributeType
        setsAttr.isOptional = true

        evaluationEntity.properties = [evalMatchingKeyAttr, flagNameAttr, treatmentAttr, configAttr, setsAttr]

        // Compound index for efficient queries
        let compoundIndex = NSFetchIndexDescription(name: "byMatchingKeyAndFlagName", elements: [
            NSFetchIndexElementDescription(property: evalMatchingKeyAttr, collationType: .binary),
            NSFetchIndexElementDescription(property: flagNameAttr, collationType: .binary)
        ])
        evaluationEntity.indexes = [compoundIndex]

        model.entities = [clientSessionEntity, evaluationEntity]
        return model
    }

    private static func storeURL(for databaseName: String) -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("SplitThin", isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("\(databaseName).sqlite")
    }
}
