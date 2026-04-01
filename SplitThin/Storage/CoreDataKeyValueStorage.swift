import Foundation
import CoreData
import Logging

enum StorageError: Error {
    case entityNotFound
}

final class CoreDataKeyValueStorage: PersistentKeyValueStorage, @unchecked Sendable {

    private static let entityName = "KeyValueEntry"
    private let container: NSPersistentContainer

    init(databaseName: String) {
        container = NSPersistentContainer(name: databaseName, managedObjectModel: Self.createModel())

        let description = NSPersistentStoreDescription()
        description.url = Self.storeURL(for: databaseName)
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error {
                Logger.e("CoreDataKeyValueStorage: Failed to load store '\(databaseName)': \(error)")
            }
        }
    }

    func read(key: String) async -> Data? {
        try? await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "key == %@", key)
            request.fetchLimit = 1
            return try context.fetch(request).first?.value(forKey: "value") as? Data
        }
    }

    func write(key: String, value: Data) async throws {
        try await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "key == %@", key)
            request.fetchLimit = 1

            let entry: NSManagedObject
            if let existing = try context.fetch(request).first {
                entry = existing
            } else {
                guard let entity = NSEntityDescription.entity(forEntityName: Self.entityName, in: context) else {
                    throw StorageError.entityNotFound
                }
                entry = NSManagedObject(entity: entity, insertInto: context)
                entry.setValue(key, forKey: "key")
            }

            entry.setValue(value, forKey: "value")
            try context.save()
        }
    }

    func remove(key: String) async throws {
        try await withContext { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "key == %@", key)

            for object in try context.fetch(request) {
                context.delete(object)
            }
            try context.save()
        }
    }

    // MARK: - Private

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

    private static func createModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = entityName
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let keyAttribute = NSAttributeDescription()
        keyAttribute.name = "key"
        keyAttribute.attributeType = .stringAttributeType

        let valueAttribute = NSAttributeDescription()
        valueAttribute.name = "value"
        valueAttribute.attributeType = .binaryDataAttributeType

        entity.properties = [keyAttribute, valueAttribute]
        model.entities = [entity]

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
