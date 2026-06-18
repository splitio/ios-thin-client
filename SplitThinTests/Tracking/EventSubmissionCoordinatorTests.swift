import XCTest
@testable import SplitThin

final class DefaultEventSubmissionCoordinatorTest: XCTestCase {

    private var eventTask: EventTaskMock!
    private var observer: ObserverSpy!
    private var coordinator: DefaultEventSubmissionCoordinator!

    override func setUp() {
        super.setUp()
        eventTask = EventTaskMock()
        observer = ObserverSpy()
        coordinator = DefaultEventSubmissionCoordinator(eventTask: eventTask, observer: observer)
    }

    func testTriggerSubmissionRunsTask() async {
        await coordinator.triggerSubmission(reason: .flush)

        XCTAssertEqual(eventTask.runCallCount, 1)
    }

    func testConcurrentTriggersAreDeduplicated() async {
        eventTask = EventTaskMock()
        observer = ObserverSpy()
        coordinator = DefaultEventSubmissionCoordinator(eventTask: eventTask, observer: observer)

        // Simulate a slow task
        let slowTask = EventTaskSlowMock()
        let slowCoordinator = DefaultEventSubmissionCoordinator(eventTask: slowTask, observer: observer)

        async let trigger1: Void = slowCoordinator.triggerSubmission(reason: .interval)
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        async let trigger2: Void = slowCoordinator.triggerSubmission(reason: .queue)

        await trigger1
        await trigger2

        XCTAssertEqual(slowTask.runCallCount, 1)
    }

    func testUnauthorizedDisablesSubmissions() async {
        eventTask.runResult = .unauthorized

        await coordinator.triggerSubmission(reason: .flush)
        XCTAssertEqual(eventTask.runCallCount, 1)
        XCTAssertTrue(observer.eventNames.contains("authUnauthorized"))

        await coordinator.triggerSubmission(reason: .flush)
        XCTAssertEqual(eventTask.runCallCount, 1, "Task should not run again after 401")
    }
}

private final class EventTaskSlowMock: EventTask, @unchecked Sendable {
    var runCallCount = 0

    func run() async -> EventTaskResult {
        runCallCount += 1
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        return .success
    }
}
