import CoreData
import XCTest
@testable import SplitThin

final class CoreDataContextExecutorTests: XCTestCase {

    private enum TestError: Error { case boom }

    private func makeExecutor() -> CoreDataContextExecutor {
        let entity = NSEntityDescription()
        entity.name = "Item"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let nameAttr = NSAttributeDescription()
        nameAttr.name = "name"
        nameAttr.attributeType = .stringAttributeType
        entity.properties = [nameAttr]

        let model = NSManagedObjectModel()
        model.entities = [entity]

        let container = NSPersistentContainer(name: "test", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }
        return CoreDataContextExecutor(container: container)
    }

    func testReadDoesNotWaitForInFlightWrite() async throws {
        let executor = makeExecutor()
        let writerStarted = expectation(description: "writer started")
        let readFinished = expectation(description: "read finished")
        let releaseWriter = DispatchSemaphore(value: 0)

        let write = Task {
            try await executor.write { _ in
                writerStarted.fulfill()
                releaseWriter.wait()
            }
        }
        await fulfillment(of: [writerStarted], timeout: 1)

        let read = Task {
            try await executor.read { _ in }
            readFinished.fulfill()
        }
        await fulfillment(of: [readFinished], timeout: 1)

        releaseWriter.signal()
        try await write.value
        try await read.value
    }

    // A failed write must not leave pending deletes/inserts on the shared writer
    // context — otherwise the next successful save would flush them.
    func testFailedWriteDoesNotLeakPendingChangesIntoNextSave() async throws {
        let executor = makeExecutor()

        try await executor.write { context in
            guard let entity = NSEntityDescription.entity(forEntityName: "Item", in: context) else {
                throw StorageError.entityNotFound
            }
            let item = NSManagedObject(entity: entity, insertInto: context)
            item.setValue("keep-me", forKey: "name")
            try context.save()
        }

        do {
            try await executor.write { context in
                let request = NSFetchRequest<NSManagedObject>(entityName: "Item")
                for object in try context.fetch(request) {
                    context.delete(object)
                }
                throw TestError.boom
            }
            XCTFail("expected write to throw")
        } catch TestError.boom {
            // expected
        }

        try await executor.write { context in
            try context.save()
        }

        let count = try await executor.read { context in
            try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "Item"))
        }
        XCTAssertEqual(count, 1, "Failed write must not delete rows via a later save")
    }
}
