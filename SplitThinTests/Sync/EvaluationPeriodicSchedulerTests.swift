import XCTest
@testable import SplitThin

final class EvaluationPeriodicSchedulerTests: XCTestCase {

    private let target = Target(matchingKey: "user1", trafficType: "user")

    private func makeScheduler(fetchCoordinator: EvaluationFetchCoordinatorMock, intervalSeconds: Int) -> DefaultEvaluationPeriodicScheduler {
        DefaultEvaluationPeriodicScheduler(
            fetchCoordinator: fetchCoordinator,
            evaluationRepository: EvaluationRepositoryMock(),
            observer: ObserverSpy(),
            target: target,
            filters: nil,
            intervalSeconds: intervalSeconds
        )
    }

    func testStartPollsAtInterval() {
        let fetchCoordinator = EvaluationFetchCoordinatorMock()
        let polled = expectation("poll triggered")
        polled.assertForOverFulfill = false
        fetchCoordinator.onFetchCallback = { polled.fulfill() }

        let scheduler = makeScheduler(fetchCoordinator: fetchCoordinator, intervalSeconds: 1)
        scheduler.start()

        waitFor(polled, timeout: 3)
        scheduler.stop()
    }

    // Start() while already running must be a no-op
    func testStartTwiceDoesNotLeakSecondLoop() {
        let fetchCoordinator = EvaluationFetchCoordinatorMock()
        let scheduler = makeScheduler(fetchCoordinator: fetchCoordinator, intervalSeconds: 1)

        scheduler.start()
        scheduler.start() // must be a no-op

        sleep(seconds: 1.5) // exactly one poll
        scheduler.stop()
        let pollsByStop = fetchCoordinator.fetchCalls.count

        XCTAssertEqual(pollsByStop, 1, "start() called twice must run a single polling loop")

        // stop() must halt polling; a leaked loop would keep fetching past stop().
        sleep(seconds: 1.5)
        XCTAssertEqual(fetchCoordinator.fetchCalls.count, pollsByStop, "stop() must halt all polling")
    }

    func testSchedulerDeallocatesWhenDroppedWithoutStop() {
        weak var weakScheduler: DefaultEvaluationPeriodicScheduler?
        autoreleasepool {
            let scheduler = makeScheduler(fetchCoordinator: EvaluationFetchCoordinatorMock(), intervalSeconds: 1)
            weakScheduler = scheduler
            scheduler.start()
            // Drop the only strong reference at end of scope WITHOUT calling stop().
        }

        waitUntil(timeout: 4) { weakScheduler == nil }
        XCTAssertNil(weakScheduler, "Scheduler must be reclaimable even if stop() is never called")
    }
}
