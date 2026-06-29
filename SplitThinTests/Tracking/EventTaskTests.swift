import XCTest
@testable import SplitThin

final class DefaultEventTaskTest: XCTestCase {

    private var storage: EventsStorageMock!
    private var serializer: EventSerializerMock!
    private var submitter: HttpEventsSubmitterMock!
    private var observer: ObserverSpy!
    private var task: DefaultEventTask!

    private let target = Target(matchingKey: "user1", trafficType: "user")

    override func setUp() {
        super.setUp()
        storage = EventsStorageMock()
        serializer = EventSerializerMock()
        submitter = HttpEventsSubmitterMock()
        observer = ObserverSpy()
        task = DefaultEventTask(storage: storage, serializer: serializer, submitter: submitter, observer: observer, target: target)
    }

    func testRunWithEmptyStorageReturnsTrue() async {
        storage.batchToReturn = []

        let result = await task.run()

        XCTAssertEqual(result, .success)
        XCTAssertEqual(submitter.submitCalls.count, 0)
    }

    func testRunSubmitsBatchAndRemovesFromStorage() async {
        let events = [EventEntity(trafficType: "user", eventType: "click")]
        storage.batchToReturn = events
        serializer.dataToReturn = Data("[]".utf8)

        let result = await task.run()

        XCTAssertEqual(result, .success)
        XCTAssertEqual(serializer.serializeCalls.count, 1)
        XCTAssertEqual(submitter.submitCalls.count, 1)
        XCTAssertEqual(storage.removedEvents.count, 1)
        XCTAssertEqual(storage.removedEvents[0].count, 1)
        XCTAssertTrue(observer.eventNames.contains("eventsPostSucceeded"))
    }

    func testRunOnSubmitFailureReturnsFalseAndNotifiesObserver() async {
        let events = [EventEntity(trafficType: "user", eventType: "click")]
        storage.batchToReturn = events
        submitter.shouldThrow = true

        let result = await task.run()

        XCTAssertEqual(result, .failed)
        XCTAssertTrue(observer.eventNames.contains("eventsPostFailed"))
        XCTAssertEqual(storage.removedEvents.count, 0)
    }

    func testRunOnSerializeFailureReturnsFalse() async {
        let events = [EventEntity(trafficType: "user", eventType: "click")]
        storage.batchToReturn = events
        serializer.shouldThrow = true

        let result = await task.run()

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(submitter.submitCalls.count, 0)
    }
}
