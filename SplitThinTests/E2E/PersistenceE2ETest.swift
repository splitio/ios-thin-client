import XCTest
import Http
@testable import SplitThin

final class PersistenceE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!
    private var factory: SplitFactory!
    private var factory2: SplitFactory!

    override func setUp() {
        super.setUp()
        httpMock = SecureHttpClientMock()
    }

    override func tearDown() async throws {
        await factory?.destroy()
        await factory2?.destroy()
        factory = nil
        factory2 = nil
        httpMock = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    func testPersistedCacheRehydratesOnSameKeyAndAttributes() async throws {
        let prefix = "persist_e2e_\(UUID().uuidString.prefix(8))"

        // First factory: fetch and persist evaluations for user_a
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cached_flag"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        let target = Target(matchingKey: "user_a", trafficType: "user")
        factory = try buildFactory(httpClient: httpMock, target: target, prefix: prefix)
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        // Give persistence a moment to write (it's non-blocking)
        sleep(seconds: 0.5)

        await factory.destroy()
        factory = nil

        // Second factory: same prefix/key — should load from cache
        let httpMock2 = SecureHttpClientMock()
        httpMock2.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cached_flag"]))

        let sdkReady2 = expectation("SDK ready 2")
        let listener2 = TestEventListener(readyExpectation: sdkReady2)
        factory2 = try buildFactory(httpClient: httpMock2, target: target, prefix: prefix)
        factory2.client.addEventListener(listener2)
        waitFor(sdkReady2, timeout: 5)

        let result = factory2.client.getTreatment("cached_flag")
        XCTAssertEqual(result.treatment, "on", "Cached flag should be available after rehydration")
    }

    func testCacheInvalidatedWhenAttributesChange() async throws {
        let prefix = "persist_e2e_attr_\(UUID().uuidString.prefix(8))"

        // Factory A: persist evaluations for user_a with attributes ["plan": "pro"]
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cached_flag"]))

        let sdkReady = expectation("SDK ready A")
        let listenerA = TestEventListener(readyExpectation: sdkReady)
        let targetA = Target(matchingKey: "user_a", attributes: ["plan": "pro"], trafficType: "user")
        factory = try buildFactory(httpClient: httpMock, target: targetA, prefix: prefix)
        factory.client.addEventListener(listenerA)
        waitFor(sdkReady)

        // Give persistence a moment to write (it's non-blocking)
        sleep(seconds: 0.5)

        await factory.destroy()
        factory = nil

        // Factory B: same matchingKey, different attributes — cache should be invalidated
        let httpMock2 = SecureHttpClientMock()
        httpMock2.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cached_flag"]))

        let sdkReady2 = expectation("SDK ready B")
        let listenerB = TestEventListener(readyExpectation: sdkReady2)
        let targetB = Target(matchingKey: "user_a", attributes: ["plan": "free"], trafficType: "user")
        factory2 = try buildFactory(httpClient: httpMock2, target: targetB, prefix: prefix)
        factory2.client.addEventListener(listenerB)
        waitFor(sdkReady2, timeout: 5)

        XCTAssertEqual(
            httpMock2.fetchEvaluationsCalls.count, 1,
            "Factory B should have fired a fresh network request because attributes changed (cache invalidated)"
        )
    }

    func testEnablingConfigsOnSecondRunServesConfigFromResponse() async throws {
        let prefix = "persist_e2e_configs_\(UUID().uuidString.prefix(8))"
        let target = Target(matchingKey: "user_a", bucketingKey: "bucket_1", trafficType: "user")

        // First run: configsEnabled = false. A full sync (since=-1) returns the flag without config.
        let server1 = SinceAwareHttpClientMock(
            authData: AuthE2ETest.mockAuthResponse(),
            fullSyncData: mockEvaluationsData(flags: ["my_flag"], till: 1000),
            upToDateData: mockEvaluationsData(flags: [], since: 1000, till: 1000)
        )

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(retryableHttpClient: server1, target: target, configsEnabled: false, prefix: prefix)
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        let firstRun = factory.client.getTreatment("my_flag")
        XCTAssertEqual(firstRun.treatment, "on")
        XCTAssertNil(firstRun.config, "With configs disabled the flag should not carry a config")

        // Give persistence a moment to write (it's non-blocking)
        sleep(seconds: 0.5)

        await factory.destroy()
        factory = nil

        // Second run: same matchingKey + bucketingKey, but now configsEnabled = true.
        //
        // The server only returns config on a full sync (since=-1). If enabling configs did NOT
        // invalidate the stored changeNumber, the SDK would send since=<stored> and get an empty
        // "you're up to date" response, keeping the config-less cache from run 1. That's exactly
        // the bug this test guards against: only the cache invalidation makes run 2 send since=-1.
        let server2 = SinceAwareHttpClientMock(
            authData: AuthE2ETest.mockAuthResponse(),
            fullSyncData: mockEvaluationsData(flags: ["my_flag"], config: "{\"color\":\"blue\"}", till: 1000),
            upToDateData: mockEvaluationsData(flags: [], since: 1000, till: 1000),
            // Make the fresh fetch land after the (stale) cache load so the assertion is deterministic.
            evaluationsDelay: 0.3
        )

        let sdkReady2 = expectation("SDK ready 2")
        let listener2 = TestEventListener(readyExpectation: sdkReady2)
        factory2 = try buildFactory(retryableHttpClient: server2, target: target, configsEnabled: true, prefix: prefix)
        factory2.client.addEventListener(listener2)
        waitFor(sdkReady2, timeout: 5)

        let secondRun = factory2.client.getTreatment("my_flag")
        XCTAssertEqual(secondRun.treatment, "on")
        XCTAssertEqual(secondRun.config, "{\"color\":\"blue\"}", "After enabling configs the response config should be served")
    }
}

// Emulates the backend's since-based behavior for /evaluations
private final class SinceAwareHttpClientMock: RetryableHttpClient, @unchecked Sendable {

    private let authData: Data
    private let fullSyncData: Data
    private let upToDateData: Data
    private let evaluationsDelay: TimeInterval

    init(authData: Data, fullSyncData: Data, upToDateData: Data, evaluationsDelay: TimeInterval = 0) {
        self.authData = authData
        self.fullSyncData = fullSyncData
        self.upToDateData = upToDateData
        self.evaluationsDelay = evaluationsDelay
    }

    func execute(_ endpoint: Endpoint, category: RequestCategory, body: Data?) async throws -> HttpResponse {
        switch category {
            case .auth:
                return HttpResponse(code: 200, data: authData)
            case .evaluations:
                let isFullSync = endpoint.url.absoluteString.contains("since=-1")
                if evaluationsDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(evaluationsDelay * 1_000_000_000))
                }
                return HttpResponse(code: 200, data: isFullSync ? fullSyncData : upToDateData)
            default:
                return HttpResponse(code: 200, data: nil)
        }
    }
}
