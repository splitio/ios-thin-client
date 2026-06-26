import XCTest
@testable import SplitThin

final class SyncManagerTests: XCTestCase {

    private var syncManager: DefaultSyncManager!
    private var polling: PeriodicSchedulerMock!
    private var streaming: StreamingMock!
    private var observer: ObserverSpy!
    private var evaluationRepository: EvaluationRepositoryMock!
    private var eventsManager: SplitEventsManagerMock!

    private let target = Target(matchingKey: "user1", trafficType: "user")

    override func setUp() {
        super.setUp()
        polling = PeriodicSchedulerMock()
        streaming = StreamingMock()
        observer = ObserverSpy()
        evaluationRepository = EvaluationRepositoryMock()
        eventsManager = SplitEventsManagerMock()
    }

    private let evaluationStorage = EvaluationStorageMock()

    private func createSyncManager(mode: SyncMode) -> DefaultSyncManager {
        DefaultSyncManager(syncMode: mode, evaluationRepository: evaluationRepository, observer: observer, evaluationStorage: evaluationStorage, eventsManager: eventsManager, periodicScheduler: polling, streaming: streaming, target: target)
    }

    // MARK: - Fallback to polling

    func testFallbackToPollingStartsPollingInStreamingMode() {
        syncManager = createSyncManager(mode: .streaming)

        syncManager.fallbackToPolling()

        XCTAssertEqual(polling.startCalls, 1)
    }

    func testFallbackToPollingIgnoredInPollingMode() {
        syncManager = createSyncManager(mode: .polling)

        syncManager.fallbackToPolling()

        XCTAssertEqual(polling.startCalls, 0)
    }

    func testFallbackToPollingIgnoredInSingleSyncMode() {
        syncManager = createSyncManager(mode: .singleSync)

        syncManager.fallbackToPolling()

        XCTAssertEqual(polling.startCalls, 0)
    }

    // MARK: - Pause Tests

#if !os(macOS)
    func testPauseStopsPollingAndStreaming() {
        syncManager = createSyncManager(mode: .polling)

        syncManager.pause()

        XCTAssertEqual(polling.stopCalls, 1)
        XCTAssertEqual(streaming.pauseCallCount, 1)
    }

    func testPauseMultipleTimesOnlyPausesOnce() {
        syncManager = createSyncManager(mode: .polling)

        syncManager.pause()
        syncManager.pause()
        syncManager.pause()

        XCTAssertEqual(polling.stopCalls, 1)
        XCTAssertEqual(streaming.pauseCallCount, 1)
    }

    // MARK: - Resume Tests

    func testResumePollingModeStartsPolling() {
        syncManager = createSyncManager(mode: .polling)

        syncManager.pause()
        syncManager.resume()

        XCTAssertEqual(polling.startCalls, 1)
        XCTAssertEqual(streaming.resumeCallCount, 0)
    }

    func testResumeStreamingModeResumesStreaming() {
        syncManager = createSyncManager(mode: .streaming)

        syncManager.pause()
        syncManager.resume()

        XCTAssertEqual(polling.startCalls, 0)
        XCTAssertEqual(streaming.resumeCallCount, 1)
    }

    func testResumeSingleSyncModeDoesNothing() {
        syncManager = createSyncManager(mode: .singleSync)

        syncManager.pause()
        syncManager.resume()

        XCTAssertEqual(polling.startCalls, 0)
        XCTAssertEqual(streaming.resumeCallCount, 0)
    }

    func testResumeWithoutPauseDoesNothing() {
        syncManager = createSyncManager(mode: .polling)

        syncManager.resume()

        XCTAssertEqual(polling.startCalls, 0)
        XCTAssertEqual(streaming.resumeCallCount, 0)
    }

    func testResumeAfterResumeDoesNothing() {
        syncManager = createSyncManager(mode: .polling)

        syncManager.pause()
        syncManager.resume()
        syncManager.resume()

        XCTAssertEqual(polling.startCalls, 1)
    }
#endif
}

// MARK: - Mocks

final class PeriodicSchedulerMock: EvaluationPeriodicScheduler, @unchecked Sendable {
    var startCalls = 0
    var stopCalls = 0
    var setTargetCalls = 0
    var lastTargetSet: Target?

    func start() {
        startCalls += 1
    }

    func stop() {
        stopCalls += 1
    }

    func setTarget(_ target: Target) {
        setTargetCalls += 1
        lastTargetSet = target
    }
}

