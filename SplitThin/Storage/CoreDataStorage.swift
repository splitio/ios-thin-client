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
    private static let eventEntity = "Event"
    private static let telemetrySessionEntity = "TelemetrySession"

    private let container: NSPersistentContainer

    init(databaseName: String) {
        container = NSPersistentContainer(name: databaseName, managedObjectModel: Self.createModel())

        let description = NSPersistentStoreDescription()
        description.url = Self.storeURL(for: databaseName)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error {
                Logger.e("CoreDataStorage: Failed to load store '\(databaseName)': \(error)")
            }
        }
    }

    // MARK: - ClientSession Operations

    func upsertClientSession(matchingKey: String, bucketingKey: String?, attributesHash: String, attributes: [String: Any]?, changeNumber: Int64) async throws {
        try await withContext { context in
            let deleteRequest = NSFetchRequest<NSManagedObject>(entityName: Self.clientSessionEntity)
            deleteRequest.predicate = self.sessionPredicate(matchingKey: matchingKey, bucketingKey: bucketingKey)
            for object in try context.fetch(deleteRequest) {
                context.delete(object)
            }

            guard let entity = NSEntityDescription.entity(forEntityName: Self.clientSessionEntity, in: context) else {
                throw StorageError.entityNotFound
            }
            let session = NSManagedObject(entity: entity, insertInto: context)
            session.setValue(matchingKey, forKey: "matchingKey")
            session.setValue(bucketingKey, forKey: "bucketingKey")
            session.setValue(changeNumber, forKey: "changeNumber")
            session.setValue(self.encodeAttributes(attributes), forKey: "attributes")
            session.setValue(attributesHash, forKey: "attributesHash")

            try context.save()
        }
    }

    func getAttributesHash(matchingKey: String, bucketingKey: String?) async -> String? {
        try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.clientSessionEntity)
            request.predicate = self.sessionPredicate(matchingKey: matchingKey, bucketingKey: bucketingKey)
            request.fetchLimit = 1
            return try context.fetch(request).first?.value(forKey: "attributesHash") as? String
        }
    }

    func getChangeNumber(matchingKey: String, bucketingKey: String?) async -> Int64? {
        try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.clientSessionEntity)
            request.predicate = self.sessionPredicate(matchingKey: matchingKey, bucketingKey: bucketingKey)
            request.fetchLimit = 1
            return try context.fetch(request).first?.value(forKey: "changeNumber") as? Int64
        }
    }

    func deleteClientSession(matchingKey: String, bucketingKey: String?) async throws {
        try await withContext { context in
            let sessionRequest = NSFetchRequest<NSManagedObject>(entityName: Self.clientSessionEntity)
            sessionRequest.predicate = self.sessionPredicate(matchingKey: matchingKey, bucketingKey: bucketingKey)
            for object in try context.fetch(sessionRequest) {
                context.delete(object)
            }

            let evalRequest = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            evalRequest.predicate = self.sessionPredicate(matchingKey: matchingKey, bucketingKey: bucketingKey)
            for object in try context.fetch(evalRequest) {
                context.delete(object)
            }

            try context.save()
        }
    }

    // MARK: - Evaluation Operations

    func upsertEvaluations(matchingKey: String, bucketingKey: String?, evaluations: [(flagName: String, treatment: String, config: String?, sets: [String]?)]) async throws {
        try await withContext { context in
            let deleteRequest = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            deleteRequest.predicate = self.sessionPredicate(matchingKey: matchingKey, bucketingKey: bucketingKey)
            for object in try context.fetch(deleteRequest) {
                context.delete(object)
            }

            for eval in evaluations {
                guard let entity = NSEntityDescription.entity(forEntityName: Self.evaluationEntity, in: context) else {
                    throw StorageError.entityNotFound
                }
                let evaluation = NSManagedObject(entity: entity, insertInto: context)
                evaluation.setValue(matchingKey, forKey: "matchingKey")
                evaluation.setValue(bucketingKey, forKey: "bucketingKey")
                evaluation.setValue(eval.flagName, forKey: "flagName")
                evaluation.setValue(eval.treatment, forKey: "treatment")
                evaluation.setValue(eval.config, forKey: "config")
                evaluation.setValue(self.encodeSets(eval.sets), forKey: "sets")
            }

            try context.save()
        }
    }

    func getEvaluation(matchingKey: String, bucketingKey: String?, flagName: String) async -> (treatment: String, config: String?, sets: [String]?)? {
        try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.sessionPredicate(matchingKey: matchingKey, bucketingKey: bucketingKey),
                NSPredicate(format: "flagName == %@", flagName)
            ])
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

    func getEvaluations(matchingKey: String, bucketingKey: String?, flagNames: [String]) async -> [(flagName: String, treatment: String, config: String?, sets: [String]?)] {
        guard !flagNames.isEmpty else { return [] }

        return (try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.sessionPredicate(matchingKey: matchingKey, bucketingKey: bucketingKey),
                NSPredicate(format: "flagName IN %@", flagNames)
            ])

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

    func getAllEvaluations(matchingKey: String, bucketingKey: String?) async -> [(flagName: String, treatment: String, config: String?, sets: [String]?)] {
        (try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            request.predicate = self.sessionPredicate(matchingKey: matchingKey, bucketingKey: bucketingKey)

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

    func getFlagNames(matchingKey: String, bucketingKey: String?) async -> [String] {
        (try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.evaluationEntity)
            request.predicate = self.sessionPredicate(matchingKey: matchingKey, bucketingKey: bucketingKey)
            request.propertiesToFetch = ["flagName"]

            return try context.fetch(request).compactMap { $0.value(forKey: "flagName") as? String }
        }) ?? []
    }

    // MARK: - Event Operations

    func addEvent(_ dto: EventDTO) async throws {
        try await addEvents([dto])
    }

    func addEvents(_ dtos: [EventDTO]) async throws {
        guard !dtos.isEmpty else { return }

        try await withContext { context in
            guard let entity = NSEntityDescription.entity(forEntityName: Self.eventEntity, in: context) else {
                throw StorageError.entityNotFound
            }

            for dto in dtos {
                let event = NSManagedObject(entity: entity, insertInto: context)
                event.setValue(dto.id.uuidString, forKey: "id")
                event.setValue(dto.key, forKey: "key")
                event.setValue(dto.trafficType, forKey: "trafficType")
                event.setValue(dto.eventType, forKey: "eventType")
                event.setValue(dto.value ?? 0, forKey: "value")
                event.setValue(dto.value != nil, forKey: "hasValue")
                event.setValue(dto.properties, forKey: "properties")
                event.setValue(dto.timestamp, forKey: "timestamp")
            }

            try context.save()
        }
    }

    func getEventBatch(size: Int) async -> [EventDTO] {
        (try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.eventEntity)
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            request.fetchLimit = size

            return try context.fetch(request).compactMap { result -> EventDTO? in
                guard let idString = result.value(forKey: "id") as? String, let id = UUID(uuidString: idString) else {
                    return nil
                }

                let hasValue = result.value(forKey: "hasValue") as? Bool ?? false
                return EventDTO(id: id, key: result.value(forKey: "key") as? String ?? "", trafficType: result.value(forKey: "trafficType") as? String ?? "", eventType: result.value(forKey: "eventType") as? String ?? "", value: hasValue ? result.value(forKey: "value") as? Double : nil, properties: result.value(forKey: "properties") as? String, timestamp: result.value(forKey: "timestamp") as? Double ?? 0)
            }
        }) ?? []
    }

    func countEvents() async -> Int {
        (try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.eventEntity)
            return try context.count(for: request)
        }) ?? 0
    }

    func removeEvents(ids: [String]) async {
        guard !ids.isEmpty else { return }

        try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.eventEntity)
            request.predicate = NSPredicate(format: "id IN %@", ids)
            for object in try context.fetch(request) {
                context.delete(object)
            }
            try context.save()
        }
    }

    func clearEvents() async {
        try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.eventEntity)
            for object in try context.fetch(request) {
                context.delete(object)
            }
            try context.save()
        }
    }

    // MARK: - TelemetrySession Operations

    func upsertTelemetrySession(sessionId: String, metricsJson: String, timestamp: Double) async throws {
        try await withContext { context in
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: Self.telemetrySessionEntity)
            fetchRequest.predicate = NSPredicate(format: "sessionId == %@", sessionId)
            fetchRequest.fetchLimit = 1

            let existing = try context.fetch(fetchRequest).first

            if let existing {
                existing.setValue(metricsJson, forKey: "metricsJson")
                existing.setValue(timestamp, forKey: "lastUpdateTimestamp")
            } else {
                guard let entity = NSEntityDescription.entity(forEntityName: Self.telemetrySessionEntity, in: context) else {
                    throw StorageError.entityNotFound
                }
                let record = NSManagedObject(entity: entity, insertInto: context)
                record.setValue(sessionId, forKey: "sessionId")
                record.setValue(metricsJson, forKey: "metricsJson")
                record.setValue(timestamp, forKey: "lastUpdateTimestamp")
            }

            try context.save()
        }
    }

    func getTelemetrySessions(excluding sessionId: String) async -> [(sessionId: String, metricsJson: String, lastUpdateTimestamp: Double)] {
        (try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.telemetrySessionEntity)
            request.predicate = NSPredicate(format: "sessionId != %@", sessionId)
            request.sortDescriptors = [NSSortDescriptor(key: "lastUpdateTimestamp", ascending: true)]

            return try context.fetch(request).compactMap { result -> (String, String, Double)? in
                guard let sid = result.value(forKey: "sessionId") as? String,
                      let json = result.value(forKey: "metricsJson") as? String else { return nil }
                let ts = result.value(forKey: "lastUpdateTimestamp") as? Double ?? 0
                return (sid, json, ts)
            }
        }) ?? []
    }

    func getAllTelemetrySessions() async -> [(sessionId: String, metricsJson: String, lastUpdateTimestamp: Double)] {
        (try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.telemetrySessionEntity)
            request.sortDescriptors = [NSSortDescriptor(key: "lastUpdateTimestamp", ascending: true)]

            return try context.fetch(request).compactMap { result -> (String, String, Double)? in
                guard let sid = result.value(forKey: "sessionId") as? String,
                      let json = result.value(forKey: "metricsJson") as? String else { return nil }
                let ts = result.value(forKey: "lastUpdateTimestamp") as? Double ?? 0
                return (sid, json, ts)
            }
        }) ?? []
    }

    func countTelemetrySessions() async -> Int {
        (try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.telemetrySessionEntity)
            return try context.count(for: request)
        }) ?? 0
    }

    func removeTelemetrySessions(sessionIds: [String]) async {
        guard !sessionIds.isEmpty else { return }

        try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.telemetrySessionEntity)
            request.predicate = NSPredicate(format: "sessionId IN %@", sessionIds)
            for object in try context.fetch(request) {
                context.delete(object)
            }
            try context.save()
        }
    }

    func removeOldestTelemetrySessions(keepCount: Int) async {
        try? await withContext { context in
            let countRequest = NSFetchRequest<NSManagedObject>(entityName: Self.telemetrySessionEntity)
            let total = try context.count(for: countRequest)

            guard total > keepCount else { return }

            let request = NSFetchRequest<NSManagedObject>(entityName: Self.telemetrySessionEntity)
            request.sortDescriptors = [NSSortDescriptor(key: "lastUpdateTimestamp", ascending: true)]
            request.fetchLimit = total - keepCount

            for object in try context.fetch(request) {
                context.delete(object)
            }
            try context.save()
        }
    }

    // MARK: - Private Helpers

    private func sessionPredicate(matchingKey: String, bucketingKey: String?) -> NSPredicate {
        if let bucketingKey {
            return NSPredicate(format: "matchingKey == %@ AND bucketingKey == %@", matchingKey, bucketingKey)
        }
        return NSPredicate(format: "matchingKey == %@ AND bucketingKey == nil", matchingKey)
    }

    private func encodeAttributes(_ attributes: [String: Any]?) -> String? {
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

        let sessionBucketingKeyAttr = NSAttributeDescription()
        sessionBucketingKeyAttr.name = "bucketingKey"
        sessionBucketingKeyAttr.attributeType = .stringAttributeType
        sessionBucketingKeyAttr.isOptional = true

        let attributesHashAttr = NSAttributeDescription()
        attributesHashAttr.name = "attributesHash"
        attributesHashAttr.attributeType = .stringAttributeType
        attributesHashAttr.isOptional = true

        clientSessionEntity.properties = [matchingKeyAttr, attributesAttr, attributesHashAttr, changeNumberAttr, sessionBucketingKeyAttr]

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

        let evalBucketingKeyAttr = NSAttributeDescription()
        evalBucketingKeyAttr.name = "bucketingKey"
        evalBucketingKeyAttr.attributeType = .stringAttributeType
        evalBucketingKeyAttr.isOptional = true

        evaluationEntity.properties = [evalMatchingKeyAttr, flagNameAttr, treatmentAttr, configAttr, setsAttr, evalBucketingKeyAttr]

        // Compound index for efficient queries
        let compoundIndex = NSFetchIndexDescription(name: "byMatchingKeyAndFlagName", elements: [
            NSFetchIndexElementDescription(property: evalMatchingKeyAttr, collationType: .binary),
            NSFetchIndexElementDescription(property: evalBucketingKeyAttr, collationType: .binary),
            NSFetchIndexElementDescription(property: flagNameAttr, collationType: .binary)
        ])
        evaluationEntity.indexes = [compoundIndex]

        // Event entity
        let eventEntity = NSEntityDescription()
        eventEntity.name = Self.eventEntity
        eventEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let eventIdAttr = NSAttributeDescription()
        eventIdAttr.name = "id"
        eventIdAttr.attributeType = .stringAttributeType

        let eventTrafficTypeAttr = NSAttributeDescription()
        eventTrafficTypeAttr.name = "trafficType"
        eventTrafficTypeAttr.attributeType = .stringAttributeType

        let eventEventTypeAttr = NSAttributeDescription()
        eventEventTypeAttr.name = "eventType"
        eventEventTypeAttr.attributeType = .stringAttributeType

        let eventValueAttr = NSAttributeDescription()
        eventValueAttr.name = "value"
        eventValueAttr.attributeType = .doubleAttributeType
        eventValueAttr.isOptional = true

        let eventHasValueAttr = NSAttributeDescription()
        eventHasValueAttr.name = "hasValue"
        eventHasValueAttr.attributeType = .booleanAttributeType

        let eventKeyAttr = NSAttributeDescription()
        eventKeyAttr.name = "key"
        eventKeyAttr.attributeType = .stringAttributeType

        let eventPropertiesAttr = NSAttributeDescription()
        eventPropertiesAttr.name = "properties"
        eventPropertiesAttr.attributeType = .stringAttributeType
        eventPropertiesAttr.isOptional = true

        let eventTimestampAttr = NSAttributeDescription()
        eventTimestampAttr.name = "timestamp"
        eventTimestampAttr.attributeType = .doubleAttributeType

        eventEntity.properties = [eventIdAttr, eventKeyAttr, eventTrafficTypeAttr, eventEventTypeAttr, eventValueAttr, eventHasValueAttr, eventPropertiesAttr, eventTimestampAttr]

        let eventTimestampIndex = NSFetchIndexDescription(name: "byTimestamp", elements: [
            NSFetchIndexElementDescription(property: eventTimestampAttr, collationType: .binary)
        ])
        eventEntity.indexes = [eventTimestampIndex]

        // TelemetrySession entity
        let telemetrySessionEntity = NSEntityDescription()
        telemetrySessionEntity.name = Self.telemetrySessionEntity
        telemetrySessionEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let telemetrySessionIdAttr = NSAttributeDescription()
        telemetrySessionIdAttr.name = "sessionId"
        telemetrySessionIdAttr.attributeType = .stringAttributeType

        let telemetryMetricsJsonAttr = NSAttributeDescription()
        telemetryMetricsJsonAttr.name = "metricsJson"
        telemetryMetricsJsonAttr.attributeType = .stringAttributeType

        let telemetryTimestampAttr = NSAttributeDescription()
        telemetryTimestampAttr.name = "lastUpdateTimestamp"
        telemetryTimestampAttr.attributeType = .doubleAttributeType

        telemetrySessionEntity.properties = [telemetrySessionIdAttr, telemetryMetricsJsonAttr, telemetryTimestampAttr]

        model.entities = [clientSessionEntity, evaluationEntity, eventEntity, telemetrySessionEntity]
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
