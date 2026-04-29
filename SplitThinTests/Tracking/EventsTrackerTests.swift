import XCTest
@testable import SplitThin

final class DefaultEventsTrackerTest: XCTestCase {

    private var validator: EventsValidatorMock!
    private var storage: EventsStorageMock!
    private var coordinator: EventSubmissionCoordinatorMock!
    private var observer: ObserverSpy!
    private var tracker: DefaultEventsTracker!

    override func setUp() {
        super.setUp()
        validator = EventsValidatorMock()
        storage = EventsStorageMock()
        coordinator = EventSubmissionCoordinatorMock()
        observer = ObserverSpy()
        tracker = DefaultEventsTracker(validator: validator, storage: storage, coordinator: coordinator, observer: observer)
    }

    func testTrackValidEventStoresIt() async {
        let event = EventEntity(trafficType: "user", eventType: "purchase")

        await tracker.track(event)

        XCTAssertEqual(storage.addedEvents.count, 1)
        XCTAssertEqual(storage.addedEvents[0].eventType, "purchase")
    }

    func testTrackInvalidEventDropsIt() async {
        validator.validateResult = false
        let event = EventEntity(trafficType: "", eventType: "")

        await tracker.track(event)

        XCTAssertEqual(storage.addedEvents.count, 0)
        XCTAssertTrue(observer.eventNames.contains("trackDropped"))
    }

    func testTrackTriggersQueueFlushWhenThresholdReached() async {
        storage.countToReturn = 2000
        let event = EventEntity(trafficType: "user", eventType: "click")

        await tracker.track(event)

        XCTAssertEqual(coordinator.triggerCalls.count, 1)
        XCTAssertEqual(coordinator.triggerCalls[0], .queue)
    }

    func testTrackDoesNotFlushBelowThreshold() async {
        storage.countToReturn = 100
        let event = EventEntity(trafficType: "user", eventType: "click")

        await tracker.track(event)

        XCTAssertEqual(coordinator.triggerCalls.count, 0)
    }

    func testFlushTriggersCoordinator() async {
        await tracker.flush()

        XCTAssertEqual(coordinator.triggerCalls.count, 1)
        XCTAssertEqual(coordinator.triggerCalls[0], .flush)
    }
}
