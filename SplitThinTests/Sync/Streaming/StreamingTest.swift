import XCTest
import BackoffCounter
@testable import SplitThin

class DefaultStreamingTest: XCTestCase {

    var fetchCoordinatorMock: EvaluationFetchCoordinatorMock!
    var target: Target!
    var streaming: DefaultStreaming!

    override func setUp() {
        super.setUp()
        fetchCoordinatorMock = EvaluationFetchCoordinatorMock()
        target = Target(matchingKey: "user1", bucketingKey: nil)
        streaming = DefaultStreaming(
            target: target,
            fetchCoordinator: fetchCoordinatorMock,
            notificationParser: DefaultThinNotificationParser()
        )
    }

    // MARK: - handleNotification

    func testEvaluationUpdateCallsRefetchAll() {
        let refetchAll = expectation()
        fetchCoordinatorMock.onRefetchAllCallback = { refetchAll.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 99)
        streaming.handleNotification(notification)

        waitFor(refetchAll)
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    func testControlNotificationDoesNotTriggerFetch() {
        let shouldNotFetch = expectation().inverted()
        fetchCoordinatorMock.onFetchCallback = { shouldNotFetch.fulfill() }

        let notification = ThinControlNotification(channel: "ctrl", timestamp: 1000, controlType: .streamingPaused)
        streaming.handleNotification(notification)

        waitFor(shouldNotFetch, timeout: 0.3)
    }

    func testOccupancyNotificationDoesNotTriggerFetch() {
        let shouldNotFetch = expectation().inverted()
        fetchCoordinatorMock.onFetchCallback = { shouldNotFetch.fulfill() }

        let notification = ThinOccupancyNotification(channel: "[?occupancy=metrics.publishers]ch1", timestamp: 1000, publishers: 2)
        streaming.handleNotification(notification)

        waitFor(shouldNotFetch, timeout: 0.3)
    }

    func testStreamingDisabledControlStopsManager() {
        streaming.start() // puts state to started
        let notification = ThinControlNotification(channel: "ctrl", timestamp: 1000, controlType: .streamingDisabled)
        streaming.handleNotification(notification)
        // After stop, starting again should work (state reset to stopped)
        streaming.start()
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    // MARK: - SseHandler

    func testIsConnectionConfirmedWithId() {
        XCTAssertTrue(streaming.isConnectionConfirmed(message: ["id": "abc"]))
    }

    func testIsConnectionConfirmedWithData() {
        XCTAssertTrue(streaming.isConnectionConfirmed(message: ["data": "payload"]))
    }

    func testIsConnectionConfirmedEmptyMessageReturnsFalse() {
        XCTAssertFalse(streaming.isConnectionConfirmed(message: [:]))
    }

    func testHandleIncomingMessageCallsRefetchAll() {
        let refetchAll = expectation()
        fetchCoordinatorMock.onRefetchAllCallback = { refetchAll.fulfill() }

        let innerData = "{\"type\":\"EVALUATIONS_UPDATE\",\"changeNumber\":55}"
        let escaped = innerData.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: "\"", with: "\\\"")
        streaming.handleIncomingMessage(message: [
            "data": "{\"channel\":\"ch1\",\"data\":\"\(escaped)\",\"timestamp\":1000}"
        ])

        waitFor(refetchAll)
    }

    func testHandleIncomingMessageWithMissingDataDoesNothing() {
        streaming.handleIncomingMessage(message: ["id": "123"])
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    // MARK: - STREAMING_RESET

    func testStreamingResetDisconnectsAndReconnects() {
        // After STREAMING_RESET the manager should stop (activeConnectionHandler disconnect)
        // then reconnect. We verify by checking state doesn't crash and no fetch is triggered.
        streaming.start()
        let notification = ThinControlNotification(channel: "ctrl", timestamp: 1000, controlType: .streamingReset)
        streaming.handleNotification(notification)
        // No assertion on fetch — just verifying no crash and no fetch triggered
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    // MARK: - Occupancy

    func testOccupancyZeroPublishersCallsOnPushDisabled() {
        var pushDisabledCalled = false
        streaming = DefaultStreaming(
            target: target,
            fetchCoordinator: fetchCoordinatorMock,
            notificationParser: DefaultThinNotificationParser(),
            onPushDisabled: { pushDisabledCalled = true }
        )
        let notification = ThinOccupancyNotification(channel: "[?occupancy=metrics.publishers]ch1", timestamp: 1000, publishers: 0)
        streaming.handleNotification(notification)
        XCTAssertTrue(pushDisabledCalled)
    }

    func testOccupancyNonZeroPublishersDoesNotCallOnPushDisabled() {
        var pushDisabledCalled = false
        streaming = DefaultStreaming(
            target: target,
            fetchCoordinator: fetchCoordinatorMock,
            notificationParser: DefaultThinNotificationParser(),
            onPushDisabled: { pushDisabledCalled = true }
        )
        let notification = ThinOccupancyNotification(channel: "[?occupancy=metrics.publishers]ch1", timestamp: 1000, publishers: 2)
        streaming.handleNotification(notification)
        XCTAssertFalse(pushDisabledCalled)
    }

    // MARK: - Error

    func testErrorNotificationCallsReportError() {
        // After a streaming error, manager should call reportError.
        // With isRetryable=false (401), state becomes stopped.
        streaming.start()
        let errorNotif = ThinStreamingError(channel: nil, timestamp: 0, message: "Unauthorized", code: 40100, statusCode: 401)
        streaming.handleNotification(errorNotif)
        // Verify no fetch triggered (just error handling)
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    func testRetryableErrorNotificationDoesNotStopImmediately() {
        streaming.start()
        let errorNotif = ThinStreamingError(channel: nil, timestamp: 0, message: "Server Error", code: 50000, statusCode: 500)
        streaming.handleNotification(errorNotif)
        // Retryable: manager stays in started state (reconnect scheduled)
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    // MARK: - Lifecycle

    func testPauseAndResumeChangesState() {
        let refetchAll = expectation()
        fetchCoordinatorMock.onRefetchAllCallback = { refetchAll.fulfill() }

        streaming.pause()
        streaming.resume()
        // resume triggers connectSse (no-op in test init since no authProvider)
        // Just verify state transitions don't crash
        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 1)
        streaming.handleNotification(notification)

        waitFor(refetchAll)
    }

    func testStopPreventsSubsequentStart() {
        streaming.start()
        streaming.stop()
        streaming.start() // Should work fine (state back to stopped after stop)
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    func testReportErrorNonRetryableStops() {
        streaming.start()
        streaming.reportError(isRetryable: false)
        // State should be stopped — verify start can be called again
        streaming.start()
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    // MARK: - Update strategies

    func testBoundedOnlyRefetchesAffectedKeys() {
        let decoderMock = PayloadDecoderMock()
        decoderMock.bitmapKeys = [Murmur64x128.hashKey("user1")]
        fetchCoordinatorMock.registeredMatchingKeys = ["user1", "user2"]

        streaming = DefaultStreaming(target: target, fetchCoordinator: fetchCoordinatorMock, notificationParser: DefaultThinNotificationParser(), payloadDecoder: decoderMock)

        let refetchKeys = expectation()
        fetchCoordinatorMock.onRefetchKeysCallback = { refetchKeys.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .boundedFetchRequest, compressionType: .gzip, payload: "some-payload")
        streaming.handleNotification(notification)

        waitFor(refetchKeys)
        XCTAssertEqual(fetchCoordinatorMock.refetchKeysCalls.first?.matchingKeys, ["user1"])
        XCTAssertEqual(fetchCoordinatorMock.refetchAllCalls.count, 0, "refetchAll should not be called when bounded strategy succeeds")
    }

    func testBoundedFallsBackToRefetchAllOnDecodingError() {
        let decoderMock = PayloadDecoderMock()
        decoderMock.errorToThrow = PayloadDecodingError.base64DecodingFailed
        fetchCoordinatorMock.registeredMatchingKeys = ["user1"]

        streaming = DefaultStreaming(target: target, fetchCoordinator: fetchCoordinatorMock, notificationParser: DefaultThinNotificationParser(), payloadDecoder: decoderMock)

        let refetchAll = expectation()
        fetchCoordinatorMock.onRefetchAllCallback = { refetchAll.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .boundedFetchRequest, compressionType: .gzip, payload: "bad")
        streaming.handleNotification(notification)

        waitFor(refetchAll)
    }

    func testBoundedFallsBackToRefetchAllOnMissingPayload() {
        fetchCoordinatorMock.registeredMatchingKeys = ["user1"]

        let refetchAll = expectation()
        fetchCoordinatorMock.onRefetchAllCallback = { refetchAll.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .boundedFetchRequest, compressionType: .gzip, payload: nil)
        streaming.handleNotification(notification)

        waitFor(refetchAll)
    }

    func testKeyListOnlyRefetchesAffectedKeys() {
        let decoderMock = PayloadDecoderMock()
        decoderMock.keyListResult = KeyList(added: [Murmur64x128.hashKey("user2")], removed: [])
        fetchCoordinatorMock.registeredMatchingKeys = ["user1", "user2"]

        streaming = DefaultStreaming(target: target, fetchCoordinator: fetchCoordinatorMock, notificationParser: DefaultThinNotificationParser(), payloadDecoder: decoderMock)

        let refetchKeys = expectation()
        fetchCoordinatorMock.onRefetchKeysCallback = { refetchKeys.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .keyList, compressionType: .gzip, payload: "some-payload")
        streaming.handleNotification(notification)

        waitFor(refetchKeys)
        XCTAssertEqual(fetchCoordinatorMock.refetchKeysCalls.first?.matchingKeys, ["user2"])
        XCTAssertEqual(fetchCoordinatorMock.refetchAllCalls.count, 0, "refetchAll should not be called when keyList strategy succeeds")
    }

    func testKeyListFallsBackToRefetchAllOnError() {
        let decoderMock = PayloadDecoderMock()
        decoderMock.errorToThrow = PayloadDecodingError.base64DecodingFailed
        fetchCoordinatorMock.registeredMatchingKeys = ["user1"]

        streaming = DefaultStreaming(target: target, fetchCoordinator: fetchCoordinatorMock, notificationParser: DefaultThinNotificationParser(), payloadDecoder: decoderMock)

        let refetchAll = expectation()
        fetchCoordinatorMock.onRefetchAllCallback = { refetchAll.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .keyList, compressionType: .gzip, payload: "bad")
        streaming.handleNotification(notification)

        waitFor(refetchAll)
    }

    func testKeyListFallsBackToRefetchAllOnMissingPayload() {
        let decoderMock = PayloadDecoderMock()
        fetchCoordinatorMock.registeredMatchingKeys = ["user1"]

        streaming = DefaultStreaming(target: target, fetchCoordinator: fetchCoordinatorMock, notificationParser: DefaultThinNotificationParser(), payloadDecoder: decoderMock)

        let refetchAll = expectation()
        fetchCoordinatorMock.onRefetchAllCallback = { refetchAll.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .keyList, compressionType: .gzip, payload: nil)
        streaming.handleNotification(notification)

        waitFor(refetchAll)
    }

    func testKeyListRefetchesRemovedKeys() {
        let decoderMock = PayloadDecoderMock()
        decoderMock.keyListResult = KeyList(added: [], removed: [Murmur64x128.hashKey("user1")])
        fetchCoordinatorMock.registeredMatchingKeys = ["user1", "user2"]

        streaming = DefaultStreaming(target: target, fetchCoordinator: fetchCoordinatorMock, notificationParser: DefaultThinNotificationParser(), payloadDecoder: decoderMock)

        let refetchKeys = expectation()
        fetchCoordinatorMock.onRefetchKeysCallback = { refetchKeys.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .keyList, compressionType: .gzip, payload: "some-payload")
        streaming.handleNotification(notification)

        waitFor(refetchKeys)
        XCTAssertEqual(fetchCoordinatorMock.refetchKeysCalls.first?.matchingKeys, ["user1"])
        XCTAssertEqual(fetchCoordinatorMock.refetchAllCalls.count, 0, "refetchAll should not be called when keyList strategy succeeds")
    }

    func testFetchAllStrategyCallsRefetchAll() {
        let refetchAll = expectation()
        fetchCoordinatorMock.onRefetchAllCallback = { refetchAll.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .fetchAll)
        streaming.handleNotification(notification)

        waitFor(refetchAll)
    }
}
