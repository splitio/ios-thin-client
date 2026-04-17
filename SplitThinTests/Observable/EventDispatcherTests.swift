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
        dispatcher.register(observer: observer1)
        dispatcher.register(observer: observer2)

        dispatcher.notify(event: .sdkReadyTimeoutReached)

        XCTAssertEqual(observer1.receivedEvents.count, 1)
        XCTAssertEqual(observer2.receivedEvents.count, 1)
    }

    func testNotifyWithNoObserversDoesNotCrash() {
        dispatcher.notify(event: .sdkReadyTimeoutReached)
    }

    func testFailingObserverDoesNotBlockOthers() {
        let failing = FailingObserverMock()
        let healthy = ObserverMock()
        dispatcher.register(observer: failing)
        dispatcher.register(observer: healthy)

        dispatcher.notify(event: .sdkReadyTimeoutReached)

        XCTAssertEqual(healthy.receivedEvents.count, 1)
    }

    func testMultipleEventsDeliveredInOrder() {
        let observer = ObserverMock()
        dispatcher.register(observer: observer)

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

private enum MockError: Error {
    case intentional
}

private final class FailingObserverMock: Observer, Sendable {
    func notify(event: ObservableEvent) throws {
        throw MockError.intentional
    }
}
