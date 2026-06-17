import XCTest
@testable import SplitThin

final class TelemetryObserverTests: XCTestCase {

    private var storage: TelemetryStorageMock!
    private var sut: TelemetryObserver!

    override func setUp() {
        super.setUp()
        storage = TelemetryStorageMock()
        sut = TelemetryObserver(storage: storage,
                                sessionId: "test-session",
                                config: SplitClientConfig.builder().build())
    }

    // MARK: - Metrics updates

    func testJwtFetchSucceededIncrementsCounter() async {
        sut.notify(event: .jwtFetchSucceeded(expiresAt: 999, pushEnabled: true))
        sut.notify(event: .jwtFetchSucceeded(expiresAt: 999, pushEnabled: true))

        await sut.persistNow()

        XCTAssertEqual(storage.savedSessions.count, 1)
        XCTAssertEqual(storage.savedSessions.first?.metrics.runtime.successfulJwtFetches, 2)
    }

    func testEvaluationRequestedIncrementsCounter() async {
        let target = Target(matchingKey: "user1", trafficType: "user")
        sut.notify(event: .evaluationRequested(flagName: "flag1", target: target))
        sut.notify(event: .evaluationRequested(flagName: "flag2", target: target))
        sut.notify(event: .evaluationRequested(flagName: "flag3", target: target))

        await sut.persistNow()

        XCTAssertEqual(storage.savedSessions.first?.metrics.runtime.evaluationCount, 3)
    }

    func testEvalFetchSucceededUpdatesLastSync() async {
        sut.notify(event: .evalFetchSucceeded(changeNumber: 12345))

        await sut.persistNow()

        XCTAssertEqual(storage.savedSessions.first?.metrics.runtime.lastEvaluationsSync, 12345)
    }

    func testUnhandledEventsDoNotTriggerPersist() async {
        sut.notify(event: .factoryInitStarted)
        sut.notify(event: .trackCalled)
        sut.notify(event: .streamingConnected)

        // Give debounce a chance to fire (it shouldn't)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(storage.savedSessions.isEmpty)
    }

    // MARK: - persistNow

    func testPersistNowSavesImmediately() async {
        sut.notify(event: .jwtFetchSucceeded(expiresAt: 999, pushEnabled: true))

        await sut.persistNow()

        XCTAssertEqual(storage.savedSessions.count, 1)
        XCTAssertEqual(storage.savedSessions.first?.sessionId, "test-session")
    }

    func testPersistNowWithNoUpdatesStillSaves() async {
        await sut.persistNow()

        XCTAssertEqual(storage.savedSessions.count, 1)
        XCTAssertEqual(storage.savedSessions.first?.metrics.runtime.evaluationCount, 0)
    }

    // MARK: - Session ID

    func testSessionIdIsPreserved() {
        XCTAssertEqual(sut.sessionId, "test-session")
    }
}
