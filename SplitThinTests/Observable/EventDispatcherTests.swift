import XCTest
@testable import SplitThin

final class EventDispatcherTests: XCTestCase {

    private var dispatcher: EventDispatcher!

    override func setUp() {
        super.setUp()
        dispatcher = EventDispatcher()
    }

    func testNotifyDispatchesToAllObservers() {
        let observer1 = ObserverMock()
        let observer2 = ObserverMock()
        dispatcher.register(observer1)
        dispatcher.register(observer2)

        dispatcher.notify(event: .sdkReadyTimeoutReached)

        XCTAssertEqual(observer1.receivedEvents.count, 1)
        XCTAssertEqual(observer2.receivedEvents.count, 1)
    }

    func testNotifyWithNoObserversDoesNotCrash() {
        dispatcher.notify(event: .sdkReadyTimeoutReached)
    }

    func testAllObserversReceiveEvents() {
        let observer1 = ObserverMock()
        let observer2 = ObserverMock()
        let observer3 = ObserverMock()
        dispatcher.register(observer1)
        dispatcher.register(observer2)
        dispatcher.register(observer3)

        dispatcher.notify(event: .sdkReadyTimeoutReached)

        XCTAssertEqual(observer1.receivedEvents.count, 1)
        XCTAssertEqual(observer2.receivedEvents.count, 1)
        XCTAssertEqual(observer3.receivedEvents.count, 1)
    }

    func testMultipleEventsDeliveredInOrder() {
        let observer = ObserverMock()
        dispatcher.register(observer)

        dispatcher.notify(event: .sdkReadyTimeoutReached)
        dispatcher.notify(event: .evaluationsUpdated(SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])))
        dispatcher.notify(event: .sdkReadyTimeoutReached)

        XCTAssertEqual(observer.receivedEvents.count, 3)
    }
}

// MARK: - Test helpers

private final class ObserverMock: Observer, @unchecked Sendable {
    var receivedEvents = [ObservableEvent]()

    func notify(event: ObservableEvent) {
        receivedEvents.append(event)
    }
}
