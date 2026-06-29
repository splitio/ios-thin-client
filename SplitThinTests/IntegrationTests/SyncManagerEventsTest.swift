import XCTest
@testable import SplitThin

final class SyncManagerEventsTest: XCTestCase {

    private var polling: PeriodicSchedulerMock!
    private var streaming: StreamingMock!
    private var observerSpy: ObserverSpy!

    override func setUp() {
        super.setUp()
        polling = PeriodicSchedulerMock()
        streaming = StreamingMock()
        observerSpy = ObserverSpy()
    }

    override func tearDown() {
        polling = nil
        streaming = nil
        observerSpy = nil
        super.tearDown()
    }

    private func createSyncManager(mode: SyncMode) -> DefaultSyncManager {
        DefaultSyncManager(syncMode: mode, evaluationRepository: EvaluationRepositoryMock(), observer: observerSpy, evaluationStorage: EvaluationStorageMock(), eventsManager: SplitEventsManagerMock(), periodicScheduler: polling, streaming: streaming, target: Target(matchingKey: "user1", trafficType: "user"))
    }

#if !os(macOS)
    func testPauseEmitsSyncPaused() {
        let sm = createSyncManager(mode: .polling)
        sm.pause()

        XCTAssertTrue(observerSpy.eventNames.contains("syncPaused"))
    }

    func testResumeEmitsSyncResumed() {
        let sm = createSyncManager(mode: .polling)
        sm.pause()
        sm.resume()

        XCTAssertTrue(observerSpy.eventNames.contains("syncResumed"))
    }

    func testPauseMultipleTimesEmitsSyncPausedOnce() {
        let sm = createSyncManager(mode: .polling)
        sm.pause()
        sm.pause()
        sm.pause()

        XCTAssertEqual(observerSpy.eventNames.filter { $0 == "syncPaused" }.count, 1)
    }

    func testResumeWithoutPauseDoesNotEmitSyncResumed() {
        let sm = createSyncManager(mode: .polling)
        sm.resume()

        XCTAssertFalse(observerSpy.eventNames.contains("syncResumed"))
    }
#endif
}
