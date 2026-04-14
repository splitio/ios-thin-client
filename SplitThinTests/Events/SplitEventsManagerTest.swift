import XCTest
@testable import SplitThin

final class SplitEventsManagerTest: XCTestCase {

    private var eventsManager: DefaultSplitEventsManager!

    override func setUp() {
        super.setUp()
        let config = SplitClientConfig.builder().build()
        eventsManager = DefaultSplitEventsManager(config: config)
    }

    override func tearDown() {
        eventsManager = nil
        super.tearDown()
    }

    // MARK: - Lifecycle

    func testIsReadyReturnsFalseInitially() {
        XCTAssertFalse(eventsManager.isReady())
    }

    func testIsReadyReturnsTrueAfterSdkReady() {
        eventsManager.start()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForProcessing()

        XCTAssertTrue(eventsManager.isReady())
    }

    // MARK: - SDK_READY

    func testFirstEvaluationsUpdatedTriggersOnReady() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyCallCount, 1)
    }

    func testOnReadyFiresOnlyOnce() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyCallCount, 1)
    }

    func testOnReadyReceivesCorrectMetadata() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertNotNil(listener.lastReadyMetadata)
        XCTAssertFalse(listener.lastReadyMetadata?.isInitialCacheLoad ?? true)
    }

    // MARK: - SDK_READY_FROM_CACHE

    func testEvaluationsLoadedFromCacheTriggersOnReadyFromCache() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let cacheMetadata = SdkReadyFromCacheMetadata(lastUpdateTimestamp: 12345, isInitialCacheLoad: true)
        eventsManager.notifyInternalEvent(.evaluationsLoadedFromCache(cacheMetadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyFromCacheCallCount, 1)
    }

    func testOnReadyFromCacheFiresOnlyOnce() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let cacheMetadata = SdkReadyFromCacheMetadata(isInitialCacheLoad: true)
        eventsManager.notifyInternalEvent(.evaluationsLoadedFromCache(cacheMetadata))
        eventsManager.notifyInternalEvent(.evaluationsLoadedFromCache(cacheMetadata))
        eventsManager.notifyInternalEvent(.evaluationsLoadedFromCache(cacheMetadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyFromCacheCallCount, 1)
    }

    func testOnReadyFromCacheReceivesCorrectMetadata() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let cacheMetadata = SdkReadyFromCacheMetadata(lastUpdateTimestamp: 12345, isInitialCacheLoad: true)
        eventsManager.notifyInternalEvent(.evaluationsLoadedFromCache(cacheMetadata))

        waitForMainQueue()

        XCTAssertEqual(listener.lastReadyFromCacheMetadata?.lastUpdateTimestamp, 12345)
        XCTAssertEqual(listener.lastReadyFromCacheMetadata?.isInitialCacheLoad, true)
    }

    func testReadyFromCacheCanFireBeforeReady() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let cacheMetadata = SdkReadyFromCacheMetadata(isInitialCacheLoad: true)
        eventsManager.notifyInternalEvent(.evaluationsLoadedFromCache(cacheMetadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyFromCacheCallCount, 1)
        XCTAssertEqual(listener.onReadyCallCount, 0)

        let updateMetadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(updateMetadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyFromCacheCallCount, 1)
        XCTAssertEqual(listener.onReadyCallCount, 1)
    }

    // MARK: - SDK_READY_TIMED_OUT

    func testTimeoutTriggersOnReadyTimedOut() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        eventsManager.notifyInternalEvent(.sdkReadyTimeoutReached)

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyTimedOutCallCount, 1)
    }

    func testTimeoutDoesNotFireIfAlreadyReady() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForProcessing()

        eventsManager.notifyInternalEvent(.sdkReadyTimeoutReached)

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyTimedOutCallCount, 0)
    }

    func testOnReadyTimedOutFiresOnlyOnce() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        eventsManager.notifyInternalEvent(.sdkReadyTimeoutReached)
        eventsManager.notifyInternalEvent(.sdkReadyTimeoutReached)
        eventsManager.notifyInternalEvent(.sdkReadyTimeoutReached)

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyTimedOutCallCount, 1)
    }

    // MARK: - SDK_UPDATE

    func testSecondEvaluationsUpdatedTriggersOnUpdate() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        let metadata2 = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag2"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata2))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyCallCount, 1)
        XCTAssertEqual(listener.onUpdateCallCount, 1)
    }

    func testFirstUpdateDoesNotTriggerBothReadyAndUpdate() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyCallCount, 1)
        XCTAssertEqual(listener.onUpdateCallCount, 0)
    }

    func testOnUpdateCanFireMultipleTimes() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onUpdateCallCount, 3)
    }

    func testOnUpdateReceivesCorrectMetadata() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let metadata1 = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata1))

        waitForMainQueue()

        let metadata2 = SdkUpdateMetadata(type: .segmentsUpdate, names: ["segment1", "segment2"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata2))

        waitForMainQueue()

        XCTAssertEqual(listener.lastUpdateMetadata?.type, .segmentsUpdate)
        XCTAssertEqual(listener.lastUpdateMetadata?.names, ["segment1", "segment2"])
    }

    // MARK: - Listeners

    func testAddListenerRegistersListener() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyCallCount, 1)
    }

    func testRemoveListenerUnregistersListener() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        waitForProcessing()

        eventsManager.removeListener(listener)

        waitForProcessing()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyCallCount, 0)
    }

    func testRemoveListenerByMemoryAddress() {
        let listener1 = TestEventListener()
        let listener2 = TestEventListener()
        eventsManager.addListener(listener1)
        eventsManager.addListener(listener2)
        eventsManager.start()

        waitForProcessing()

        eventsManager.removeListener(listener1)

        waitForProcessing()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertEqual(listener1.onReadyCallCount, 0)
        XCTAssertEqual(listener2.onReadyCallCount, 1)
    }

    func testMultipleListenersReceiveEvents() {
        let listener1 = TestEventListener()
        let listener2 = TestEventListener()
        let listener3 = TestEventListener()
        eventsManager.addListener(listener1)
        eventsManager.addListener(listener2)
        eventsManager.addListener(listener3)
        eventsManager.start()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertEqual(listener1.onReadyCallCount, 1)
        XCTAssertEqual(listener2.onReadyCallCount, 1)
        XCTAssertEqual(listener3.onReadyCallCount, 1)
    }

    func testRemovedListenerDoesNotReceiveEvents() {
        let listener1 = TestEventListener()
        let listener2 = TestEventListener()
        eventsManager.addListener(listener1)
        eventsManager.addListener(listener2)
        eventsManager.start()

        waitForProcessing()

        eventsManager.removeListener(listener2)

        waitForProcessing()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertEqual(listener1.onReadyCallCount, 1)
        XCTAssertEqual(listener2.onReadyCallCount, 0)
    }

    // MARK: - Stop behavior

    func testEventsNotFiredWhenStopped() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        waitForProcessing()

        eventsManager.stop()

        waitForProcessing()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyCallCount, 0)
    }

    func testStopDoesNotRemoveListeners() {
        let listener = TestEventListener()
        eventsManager.addListener(listener)
        eventsManager.start()

        waitForProcessing()

        eventsManager.stop()

        waitForProcessing()

        eventsManager.start()

        let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: ["flag1"])
        eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

        waitForMainQueue()

        XCTAssertEqual(listener.onReadyCallCount, 1)
    }

    // MARK: - Helpers

    private func waitForProcessing() {
        let expectation = expectation(description: "wait for processing queue")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    private func waitForMainQueue() {
        let expectation = expectation(description: "wait for main queue")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}
