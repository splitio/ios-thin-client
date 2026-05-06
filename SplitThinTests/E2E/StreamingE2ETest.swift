import XCTest
import Http
@testable import SplitThin

final class StreamingE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!
    private var factory: SplitFactory!

    override func setUp() {
        super.setUp()
        httpMock = SecureHttpClientMock()
    }

    override func tearDown() async throws {
        await factory?.destroy()
        factory = nil
        httpMock = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    // Mirrors Android Test 4b: SDK emits onUpdate when evaluations change via streaming push
    func testStreamingPushTriggersEvaluationUpdateAndOnUpdate() async throws {
        let target = Target(matchingKey: "user-123")
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"]))

        let sdkReady = expectation(description: "SDK ready")
        let sdkUpdate = expectation(description: "SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)

        var connectionManagerRef: DefaultStreamingConnectionManager?
        factory = try buildStreamingFactory(target: target) { fetchCoordinator in
            let cm = DefaultStreamingConnectionManager(target: target, fetchCoordinator: fetchCoordinator, notificationParser: DefaultThinNotificationParser())
            connectionManagerRef = cm
            return cm
        }
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        XCTAssertEqual(factory.client.getTreatment("flag_a").treatment, "on", "Initial treatment should be 'on'")

        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"], treatment: "off"))
        connectionManagerRef!.handleNotification(EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 2))

        waitFor(sdkUpdate)

        XCTAssertEqual(factory.client.getTreatment("flag_a").treatment, "off", "Treatment should update to 'off' after streaming push")
    }

    // Mirrors Android Test 10: SDK delays fetch based on hashing params in the notification
    func testStreamingPushAppliesStaggeredDelayBeforeFetch() async throws {
        let targetKey = "user-123"
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"]))

        let sdkReady = expectation(description: "SDK ready")
        let sdkUpdate = expectation(description: "SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)

        let (built, connectionManager) = try buildStreamingFactory(target: targetKey)
        factory = built
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        let updateIntervalMs: Int64 = 5000
        let algorithmSeed = 42
        let expectedDelay = computeExpectedDelay(key: targetKey, updateIntervalMs: updateIntervalMs, algorithmSeed: algorithmSeed)

        let notificationSentAt = Date()
        connectionManager.handleNotification(EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 2, algorithmSeed: algorithmSeed, updateIntervalMs: updateIntervalMs))

        waitFor(sdkUpdate, timeout: Double(updateIntervalMs / 1000) + 3)

        let fetchTimestamps = httpMock.fetchEvaluationsCallTimestamps
        XCTAssertGreaterThanOrEqual(fetchTimestamps.count, 2, "Expected at least 2 fetch calls")

        if fetchTimestamps.count >= 2 {
            let actualDelay = fetchTimestamps[1].timeIntervalSince(notificationSentAt)
            XCTAssertGreaterThanOrEqual(actualDelay, expectedDelay - 0.5, "Second fetch should be delayed by at least expectedDelay - 0.5s, got \(actualDelay)s, expected \(expectedDelay)s")
        }
    }

    // Mirrors Android Test 11: Streaming connection pauses and resumes
    #if !os(macOS)
    func testStreamingPauseAndResume() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"]))

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)

        let connectionManagerMock = StreamingConnectionManagerMock()
        factory = try buildStreamingFactory(target: Target(matchingKey: "user-123")) { _ in connectionManagerMock }
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        let factoryImpl = factory as! DefaultSplitFactory
        (factoryImpl.syncManager as? MobileSync)?.pause()
        XCTAssertEqual(connectionManagerMock.pauseCallCount, 1, "pause() should be forwarded to connection manager")

        (factoryImpl.syncManager as? MobileSync)?.resume()
        XCTAssertEqual(connectionManagerMock.resumeCallCount, 1, "resume() should be forwarded to connection manager")
    }
    #endif

    // MARK: - Multi-Client Push Updates

    func testPushUpdateNotifiesBothClientsIndependently() async throws {
        httpMock.fetchEvaluationsResultByKey["user-A"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"])))
        httpMock.fetchEvaluationsResultByKey["user-B"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_b"])))

        let ready1 = expectation("Client A ready")
        let ready2 = expectation("Client B ready")
        let update1 = expectation("Client A update")
        let update2 = expectation("Client B update")
        let listener1 = TestEventListener(readyExpectation: ready1, updateExpectation: update1)
        let listener2 = TestEventListener(readyExpectation: ready2, updateExpectation: update2)

        let (built, connectionManager) = try buildStreamingFactory(target: "user-A")
        factory = built
        factory.client.addEventListener(listener1)

        let client2 = factory.getClient("user-B")
        client2.addEventListener(listener2)

        waitFor(ready1, ready2)

        connectionManager.handleNotification(EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 2))

        waitFor(update1, update2)
    }

    func testPushUpdateIsolatesPerClientMetadata() async throws {
        httpMock.fetchEvaluationsResultByKey["user-A"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["feature_x"])))
        httpMock.fetchEvaluationsResultByKey["user-B"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["feature_y", "feature_z"])))

        let ready1 = expectation("Client A ready")
        let ready2 = expectation("Client B ready")
        let update1 = expectation("Client A update")
        let update2 = expectation("Client B update")
        let listener1 = TestEventListener(readyExpectation: ready1, updateExpectation: update1)
        let listener2 = TestEventListener(readyExpectation: ready2, updateExpectation: update2)

        let (built, connectionManager) = try buildStreamingFactory(target: "user-A")
        factory = built
        factory.client.addEventListener(listener1)

        let client2 = factory.getClient("user-B")
        client2.addEventListener(listener2)

        waitFor(ready1, ready2)

        connectionManager.handleNotification(EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 2))

        waitFor(update1, update2)

        let namesA = listener1.lastUpdateMetadata?.names ?? []
        let namesB = listener2.lastUpdateMetadata?.names ?? []
        XCTAssertTrue(namesA.contains("feature_x"))
        XCTAssertFalse(namesA.contains("feature_y"))
        XCTAssertTrue(namesB.contains("feature_y"))
        XCTAssertTrue(namesB.contains("feature_z"))
        XCTAssertFalse(namesB.contains("feature_x"))
    }

    // MARK: - Helpers

    /// Builds a streaming factory with a real `DefaultStreamingConnectionManager`.
    /// The returned ref is populated lazily when the streaming manager starts (after SDK ready).
    private func buildStreamingFactory(target: String) throws -> (SplitFactory, ConnectionManagerRef) {
        let t = Target(matchingKey: target)
        let ref = ConnectionManagerRef()
        let factory = try buildStreamingFactory(target: t) { fetchCoordinator in
            let cm = DefaultStreamingConnectionManager(target: t, fetchCoordinator: fetchCoordinator, notificationParser: DefaultThinNotificationParser())
            ref.value = cm
            return cm
        }
        return (factory, ref)
    }

    private class ConnectionManagerRef {
        var value: DefaultStreamingConnectionManager!
        func handleNotification(_ notification: ThinNotification) { value.handleNotification(notification) }
    }

    /// Builds a streaming factory with a custom connection manager factory (for mocks).
    private func buildStreamingFactory(target: Target, connectionManagerFactory: @escaping (EvaluationFetchCoordinator) -> StreamingConnectionManager) throws -> SplitFactory {
        let config = SplitClientConfig.builder()
                                      .setMinEvaluationRefreshRate(1)
                                      .set(syncMode: .streaming)
                                      .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpMock)
        builder.setStreamingConnectionManagerFactory(connectionManagerFactory)

        guard let factory = builder.setSdkKey(SdkKey("test-sdk-key"))
                                   .setTarget(target)
                                   .setConfig(config)
                                   .build() else {
            throw NSError(domain: "StreamingE2ETest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to build factory"])
        }
        return factory
    }

    private func computeExpectedDelay(key: String, updateIntervalMs: Int64, algorithmSeed: Int) -> TimeInterval {
        let hash = Murmur3Hash.hashString(key, UInt32(truncatingIfNeeded: algorithmSeed))
        let bucket = Int64(bitPattern: UInt64(hash)) % updateIntervalMs
        let ms = bucket < 0 ? -bucket : bucket
        return Double(ms) / 1000.0
    }
}
