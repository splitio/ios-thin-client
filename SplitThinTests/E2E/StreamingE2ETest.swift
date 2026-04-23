import XCTest
import Http
@testable import SplitThin

final class StreamingE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!

    override func setUp() {
        super.setUp()
        httpMock = SecureHttpClientMock()
    }

    override func tearDown() {
        httpMock = nil
        super.tearDown()
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
        let factory = try buildStreamingFactory(target: target, connectionManagerFactory: { fetchCoordinator in
            let cm = DefaultStreamingConnectionManager(
                target: target,
                fetchCoordinator: fetchCoordinator,
                notificationParser: DefaultThinNotificationParser()
            )
            connectionManagerRef = cm
            return cm
        })
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        XCTAssertEqual(factory.client.getTreatment("flag_a").treatment, "on",
                       "Initial treatment should be 'on'")

        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"], treatment: "off"))
        connectionManagerRef!.handleNotification(
            EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 2)
        )

        waitFor(sdkUpdate)

        XCTAssertEqual(factory.client.getTreatment("flag_a").treatment, "off",
                       "Treatment should update to 'off' after streaming push")
        await factory.destroy()
    }

    // Mirrors Android Test 10: SDK delays fetch based on hashing params in the notification
    func testStreamingPushAppliesStaggeredDelayBeforeFetch() async throws {
        let target = Target(matchingKey: "user-123")
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"]))

        let sdkReady = expectation(description: "SDK ready")
        let sdkUpdate = expectation(description: "SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)

        var connectionManagerRef: DefaultStreamingConnectionManager?
        let factory = try buildStreamingFactory(target: target, connectionManagerFactory: { fetchCoordinator in
            let cm = DefaultStreamingConnectionManager(
                target: target,
                fetchCoordinator: fetchCoordinator,
                notificationParser: DefaultThinNotificationParser()
            )
            connectionManagerRef = cm
            return cm
        })
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        let updateIntervalMs: Int64 = 5000
        let algorithmSeed = 42
        let expectedDelay = computeExpectedDelay(key: target.matchingKey,
                                                 updateIntervalMs: updateIntervalMs,
                                                 algorithmSeed: algorithmSeed)

        let notificationSentAt = Date()
        connectionManagerRef!.handleNotification(
            EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 2,
                                         algorithmSeed: algorithmSeed, updateIntervalMs: updateIntervalMs)
        )

        waitFor(sdkUpdate, timeout: Double(updateIntervalMs / 1000) + 3)

        let fetchTimestamps = httpMock.fetchEvaluationsCallTimestamps
        XCTAssertGreaterThanOrEqual(fetchTimestamps.count, 2, "Expected at least 2 fetch calls")

        if fetchTimestamps.count >= 2 {
            let actualDelay = fetchTimestamps[1].timeIntervalSince(notificationSentAt)
            XCTAssertGreaterThanOrEqual(actualDelay, expectedDelay - 0.5,
                                        "Second fetch should be delayed by at least expectedDelay - 0.5s, got \(actualDelay)s, expected \(expectedDelay)s")
        }
        await factory.destroy()
    }

    // Mirrors Android Test 11: Streaming connection pauses and resumes
    #if !os(macOS)
    func testStreamingPauseAndResume() async throws {
        let target = Target(matchingKey: "user-123")
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"]))

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)

        let connectionManagerMock = StreamingConnectionManagerMock()
        let factory = try buildStreamingFactory(target: target, connectionManagerFactory: { _ in connectionManagerMock })
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        let factoryImpl = factory as! DefaultSplitFactory
        factoryImpl.syncManager?.pause()
        XCTAssertEqual(connectionManagerMock.pauseCallCount, 1, "pause() should be forwarded to connection manager")

        factoryImpl.syncManager?.resume()
        XCTAssertEqual(connectionManagerMock.resumeCallCount, 1, "resume() should be forwarded to connection manager")

        await factory.destroy()
    }
    #endif

    // MARK: - Helpers

    private func buildStreamingFactory(
        target: Target,
        connectionManagerFactory: @escaping (EvaluationFetchCoordinator) -> StreamingConnectionManager
    ) throws -> SplitFactory {
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
            throw NSError(domain: "StreamingE2ETest", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to build factory"])
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
