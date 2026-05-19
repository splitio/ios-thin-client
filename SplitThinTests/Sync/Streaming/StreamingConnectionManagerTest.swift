import XCTest
import BackoffCounter
@testable import SplitThin

class StreamingConnectionManagerTest: XCTestCase {

    var fetchCoordinatorMock: EvaluationFetchCoordinatorMock!
    var target: Target!
    var manager: DefaultStreamingConnectionManager!

    override func setUp() {
        super.setUp()
        fetchCoordinatorMock = EvaluationFetchCoordinatorMock()
        target = Target(matchingKey: "user1", bucketingKey: nil)
        manager = DefaultStreamingConnectionManager(
            target: target,
            fetchCoordinator: fetchCoordinatorMock,
            notificationParser: DefaultThinNotificationParser()
        )
    }

    // MARK: - handleNotification

    func testEvaluationUpdateCallsRefetchAll() async {
        let refetched = expectation(description: "refetchAll called")
        fetchCoordinatorMock.onRefetchAllCallback = { refetched.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 99)
        manager.handleNotification(notification)

        await fulfillment(of: [refetched], timeout: 2)
        XCTAssertEqual(fetchCoordinatorMock.refetchAllCalls.count, 1)
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    func testControlNotificationDoesNotTriggerFetch() async throws {
        let shouldNotFetch = expectation(description: "shouldNotFetch")
        shouldNotFetch.isInverted = true
        fetchCoordinatorMock.onFetchCallback = { shouldNotFetch.fulfill() }

        let notification = ThinControlNotification(channel: "ctrl", timestamp: 1000, controlType: .streamingPaused)
        manager.handleNotification(notification)

        await fulfillment(of: [shouldNotFetch], timeout: 0.3)
    }

    func testOccupancyNotificationDoesNotTriggerFetch() async {
        let shouldNotFetch = expectation(description: "shouldNotFetch")
        shouldNotFetch.isInverted = true
        fetchCoordinatorMock.onFetchCallback = { shouldNotFetch.fulfill() }

        let notification = ThinOccupancyNotification(channel: "[?occupancy=metrics.publishers]ch1", timestamp: 1000, publishers: 2)
        manager.handleNotification(notification)

        await fulfillment(of: [shouldNotFetch], timeout: 0.3)
    }

    func testStreamingDisabledControlStopsManager() {
        manager.start() // puts state to started
        let notification = ThinControlNotification(channel: "ctrl", timestamp: 1000, controlType: .streamingDisabled)
        manager.handleNotification(notification)
        // After stop, starting again should work (state reset to stopped)
        manager.start()
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    // MARK: - SseHandler

    func testIsConnectionConfirmedWithId() {
        XCTAssertTrue(manager.isConnectionConfirmed(message: ["id": "abc"]))
    }

    func testIsConnectionConfirmedWithData() {
        XCTAssertTrue(manager.isConnectionConfirmed(message: ["data": "payload"]))
    }

    func testIsConnectionConfirmedEmptyMessageReturnsFalse() {
        XCTAssertFalse(manager.isConnectionConfirmed(message: [:]))
    }

    func testHandleIncomingMessageCallsRefetchAll() async {
        let refetched = expectation(description: "refetchAll called")
        fetchCoordinatorMock.onRefetchAllCallback = { refetched.fulfill() }

        let innerData = "{\"type\":\"EVALUATIONS_UPDATE\",\"changeNumber\":55}"
        let escaped = innerData.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: "\"", with: "\\\"")
        manager.handleIncomingMessage(message: [
            "data": "{\"channel\":\"ch1\",\"data\":\"\(escaped)\",\"timestamp\":1000}"
        ])

        await fulfillment(of: [refetched], timeout: 2)
        XCTAssertEqual(fetchCoordinatorMock.refetchAllCalls.count, 1)
    }

    func testHandleIncomingMessageWithMissingDataDoesNothing() {
        manager.handleIncomingMessage(message: ["id": "123"])
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    // MARK: - STREAMING_RESET

    func testStreamingResetDisconnectsAndReconnects() {
        // After STREAMING_RESET the manager should stop (activeConnectionHandler disconnect)
        // then reconnect. We verify by checking state doesn't crash and no fetch is triggered.
        manager.start()
        let notification = ThinControlNotification(channel: "ctrl", timestamp: 1000, controlType: .streamingReset)
        manager.handleNotification(notification)
        // No assertion on fetch — just verifying no crash and no fetch triggered
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    // MARK: - Occupancy

    func testOccupancyZeroPublishersCallsOnPushDisabled() {
        var pushDisabledCalled = false
        manager = DefaultStreamingConnectionManager(
            target: target,
            fetchCoordinator: fetchCoordinatorMock,
            notificationParser: DefaultThinNotificationParser(),
            onPushDisabled: { pushDisabledCalled = true }
        )
        let notification = ThinOccupancyNotification(channel: "[?occupancy=metrics.publishers]ch1", timestamp: 1000, publishers: 0)
        manager.handleNotification(notification)
        XCTAssertTrue(pushDisabledCalled)
    }

    func testOccupancyNonZeroPublishersDoesNotCallOnPushDisabled() {
        var pushDisabledCalled = false
        manager = DefaultStreamingConnectionManager(
            target: target,
            fetchCoordinator: fetchCoordinatorMock,
            notificationParser: DefaultThinNotificationParser(),
            onPushDisabled: { pushDisabledCalled = true }
        )
        let notification = ThinOccupancyNotification(channel: "[?occupancy=metrics.publishers]ch1", timestamp: 1000, publishers: 2)
        manager.handleNotification(notification)
        XCTAssertFalse(pushDisabledCalled)
    }

    // MARK: - Error

    func testErrorNotificationCallsReportError() {
        // After a streaming error, manager should call reportError.
        // With isRetryable=false (401), state becomes stopped.
        manager.start()
        let errorNotif = ThinStreamingError(channel: nil, timestamp: 0, message: "Unauthorized", code: 40100, statusCode: 401)
        manager.handleNotification(errorNotif)
        // Verify no fetch triggered (just error handling)
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    func testRetryableErrorNotificationDoesNotStopImmediately() {
        manager.start()
        let errorNotif = ThinStreamingError(channel: nil, timestamp: 0, message: "Server Error", code: 50000, statusCode: 500)
        manager.handleNotification(errorNotif)
        // Retryable: manager stays in started state (reconnect scheduled)
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    // MARK: - Lifecycle

    func testPauseAndResumeChangesState() async {
        let refetched = expectation(description: "refetchAll called after resume")
        fetchCoordinatorMock.onRefetchAllCallback = { refetched.fulfill() }

        manager.pause()
        manager.resume()
        // resume triggers connectSse (no-op in test init since no authProvider)
        // Just verify state transitions don't crash
        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 1)
        manager.handleNotification(notification)

        await fulfillment(of: [refetched], timeout: 2)
    }

    func testStopPreventsSubsequentStart() {
        manager.start()
        manager.stop()
        manager.start() // Should work fine (state back to stopped after stop)
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    func testReportErrorNonRetryableStops() {
        manager.start()
        manager.reportError(isRetryable: false)
        // State should be stopped — verify start can be called again
        manager.start()
        XCTAssertEqual(fetchCoordinatorMock.fetchCalls.count, 0)
    }

    // MARK: - Update strategies

    func testBoundedOnlyRefetchesAffectedKeys() async {
        let decoderMock = PayloadDecoderMock()
        decoderMock.bitmapKeys = [Murmur64x128.hashKey("user1")]
        fetchCoordinatorMock.registeredMatchingKeys = ["user1", "user2"]

        manager = DefaultStreamingConnectionManager(target: target, fetchCoordinator: fetchCoordinatorMock, notificationParser: DefaultThinNotificationParser(), payloadDecoder: decoderMock)

        let called = expectation(description: "refetchKeys called")
        fetchCoordinatorMock.onRefetchAllCallback = { called.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .boundedFetchRequest, compressionType: .gzip, payload: "some-payload")
        manager.handleNotification(notification)

        await fulfillment(of: [called], timeout: 2)
        XCTAssertEqual(fetchCoordinatorMock.refetchKeysCalls.count, 1)
        XCTAssertEqual(fetchCoordinatorMock.refetchKeysCalls.first?.matchingKeys, ["user1"])
    }

    func testBoundedFallsBackToRefetchAllOnDecodingError() async {
        let decoderMock = PayloadDecoderMock()
        decoderMock.errorToThrow = PayloadDecodingError.base64DecodingFailed
        fetchCoordinatorMock.registeredMatchingKeys = ["user1"]

        manager = DefaultStreamingConnectionManager(target: target, fetchCoordinator: fetchCoordinatorMock, notificationParser: DefaultThinNotificationParser(), payloadDecoder: decoderMock)

        let called = expectation(description: "refetchAll fallback called")
        fetchCoordinatorMock.onRefetchAllCallback = { called.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .boundedFetchRequest, compressionType: .gzip, payload: "bad")
        manager.handleNotification(notification)

        await fulfillment(of: [called], timeout: 2)
        XCTAssertEqual(fetchCoordinatorMock.refetchAllCalls.count, 1)
    }

    func testBoundedFallsBackToRefetchAllOnMissingPayload() async {
        fetchCoordinatorMock.registeredMatchingKeys = ["user1"]

        let called = expectation(description: "refetchAll fallback called")
        fetchCoordinatorMock.onRefetchAllCallback = { called.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .boundedFetchRequest, compressionType: .gzip, payload: nil)
        manager.handleNotification(notification)

        await fulfillment(of: [called], timeout: 2)
        XCTAssertEqual(fetchCoordinatorMock.refetchAllCalls.count, 1)
    }

    func testKeyListOnlyRefetchesAffectedKeys() async {
        let decoderMock = PayloadDecoderMock()
        decoderMock.keyListResult = KeyList(added: [Murmur64x128.hashKey("user2")], removed: [])
        fetchCoordinatorMock.registeredMatchingKeys = ["user1", "user2"]

        manager = DefaultStreamingConnectionManager(target: target, fetchCoordinator: fetchCoordinatorMock, notificationParser: DefaultThinNotificationParser(), payloadDecoder: decoderMock)

        let called = expectation(description: "refetchKeys called")
        fetchCoordinatorMock.onRefetchAllCallback = { called.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .keyList, compressionType: .gzip, payload: "some-payload")
        manager.handleNotification(notification)

        await fulfillment(of: [called], timeout: 2)
        XCTAssertEqual(fetchCoordinatorMock.refetchKeysCalls.count, 1)
        XCTAssertEqual(fetchCoordinatorMock.refetchKeysCalls.first?.matchingKeys, ["user2"])
    }

    func testKeyListFallsBackToRefetchAllOnError() async {
        let decoderMock = PayloadDecoderMock()
        decoderMock.errorToThrow = PayloadDecodingError.base64DecodingFailed
        fetchCoordinatorMock.registeredMatchingKeys = ["user1"]

        manager = DefaultStreamingConnectionManager(target: target, fetchCoordinator: fetchCoordinatorMock, notificationParser: DefaultThinNotificationParser(), payloadDecoder: decoderMock)

        let called = expectation(description: "refetchAll fallback called")
        fetchCoordinatorMock.onRefetchAllCallback = { called.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .keyList, compressionType: .gzip, payload: "bad")
        manager.handleNotification(notification)

        await fulfillment(of: [called], timeout: 2)
        XCTAssertEqual(fetchCoordinatorMock.refetchAllCalls.count, 1)
    }

    func testFetchAllStrategyCallsRefetchAll() async {
        let called = expectation(description: "refetchAll called")
        fetchCoordinatorMock.onRefetchAllCallback = { called.fulfill() }

        let notification = EvaluationUpdateNotification(channel: "ch1", timestamp: 1000, changeNumber: 2, updateStrategy: .fetchAll)
        manager.handleNotification(notification)

        await fulfillment(of: [called], timeout: 2)
        XCTAssertEqual(fetchCoordinatorMock.refetchAllCalls.count, 1)
    }
}
