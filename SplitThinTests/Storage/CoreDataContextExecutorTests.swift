import CoreData
import XCTest
@testable import SplitThin

final class CoreDataContextExecutorTests: XCTestCase {

    func testReadDoesNotWaitForInFlightWrite() async throws {
        let container = NSPersistentContainer(name: "test", managedObjectModel: NSManagedObjectModel())
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }

        let executor = CoreDataContextExecutor(container: container)
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
}
