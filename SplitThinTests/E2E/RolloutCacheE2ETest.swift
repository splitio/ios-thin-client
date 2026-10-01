import XCTest
import Http
@testable import SplitThin

final class RolloutCacheE2ETest: XCTestCase {

    private var factory: SplitFactory!
    private var factory2: SplitFactory!

    override func tearDown() async throws {
        await factory?.destroy()
        await factory2?.destroy()
        factory = nil
        factory2 = nil
        try await super.tearDown()
    }

    // MARK: - Spec: Expiration period is used

    func testExpiredCacheIsClearedBeforeReadyFromCache() async throws {
        let prefix = "rollout_e2e_exp_\(UUID().uuidString.prefix(8))"
        let target = Target(matchingKey: "user_exp", trafficType: "user")
        let sdkKey = "test-sdk-key"

        // Run 1: persist evaluations.
        let http1 = SecureHttpClientMock()
        http1.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cached_flag"], treatment: "from_cache"))
        let ready1 = expectation("SDK ready 1")
        factory = try buildFactory(httpClient: http1, target: target, prefix: prefix)
        factory.client.addEventListener(TestEventListener(readyExpectation: ready1))
        waitFor(ready1)
        sleep(seconds: 0.5)
        await factory.destroy()
        factory = nil

        // Age the update timestamp past the configured expiration.
        let storage = CoreDataStorage(databaseName: DefaultSplitFactoryBuilder.databaseName(prefix: prefix, apiKey: sdkKey))
        await storage.setUpdateTimestamp(Int64(Date().timeIntervalSince1970) - (11 * 86_400))

        // Run 2: expirationDays = 10. Network is delayed so any treatment at cache-ready
        // must come from disk — which should have been cleared.
        let http2 = SecureHttpClientMock()
        http2.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cached_flag"], treatment: "from_network"))
        http2.fetchDelay = 2_000_000_000

        let cacheReady = expectation("SDK ready from cache after expiration")
        let sdkReady = expectation("SDK ready after expiration")
        factory2 = try buildFactory(
            httpClient: http2,
            target: target,
            prefix: prefix,
            rolloutCacheConfiguration: RolloutCacheConfiguration.builder().set(expirationDays: 10).build()
        )
        factory2.client.addEventListener(TestEventListener(readyExpectation: sdkReady, cacheExpectation: cacheReady))
        waitFor(cacheReady, timeout: 5)

        XCTAssertEqual(
            factory2.client.getTreatment("cached_flag").treatment, "control",
            "Expired rollout cache must be cleared before loadFromStorage"
        )

        waitFor(sdkReady, timeout: 5)
        XCTAssertEqual(factory2.client.getTreatment("cached_flag").treatment, "from_network")
    }

    // MARK: - Spec: Clear on init clears cache on startup

    func testClearOnInitClearsCacheBeforeReadyFromCache() async throws {
        let prefix = "rollout_e2e_clear_\(UUID().uuidString.prefix(8))"
        let target = Target(matchingKey: "user_clear", trafficType: "user")

        let http1 = SecureHttpClientMock()
        http1.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cached_flag"], treatment: "from_cache"))
        let ready1 = expectation("SDK ready 1")
        factory = try buildFactory(httpClient: http1, target: target, prefix: prefix)
        factory.client.addEventListener(TestEventListener(readyExpectation: ready1))
        waitFor(ready1)
        sleep(seconds: 0.5)
        await factory.destroy()
        factory = nil

        let http2 = SecureHttpClientMock()
        http2.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cached_flag"], treatment: "from_network"))
        http2.fetchDelay = 2_000_000_000

        let cacheReady = expectation("SDK ready from cache with clearOnInit")
        let sdkReady = expectation("SDK ready with clearOnInit")
        factory2 = try buildFactory(
            httpClient: http2,
            target: target,
            prefix: prefix,
            rolloutCacheConfiguration: RolloutCacheConfiguration.builder().set(clearOnInit: true).build()
        )
        factory2.client.addEventListener(TestEventListener(readyExpectation: sdkReady, cacheExpectation: cacheReady))
        waitFor(cacheReady, timeout: 5)

        XCTAssertEqual(
            factory2.client.getTreatment("cached_flag").treatment, "control",
            "clearOnInit must wipe persisted evaluations before loadFromStorage"
        )

        waitFor(sdkReady, timeout: 5)
        XCTAssertEqual(factory2.client.getTreatment("cached_flag").treatment, "from_network")
    }

    // MARK: - Spec: Clear on init respects 1-day min protection

    func testClearOnInitDoesNotClearAgainWithinOneDay() async throws {
        let prefix = "rollout_e2e_minclear_\(UUID().uuidString.prefix(8))"
        let target = Target(matchingKey: "user_minclear", trafficType: "user")
        let clearOnInit = RolloutCacheConfiguration.builder().set(clearOnInit: true).build()

        // Run 1: clearOnInit wipes (empty DB) then fetches and persists.
        let http1 = SecureHttpClientMock()
        http1.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cached_flag"], treatment: "persisted"))
        let ready1 = expectation("SDK ready 1")
        factory = try buildFactory(httpClient: http1, target: target, prefix: prefix, rolloutCacheConfiguration: clearOnInit)
        factory.client.addEventListener(TestEventListener(readyExpectation: ready1))
        waitFor(ready1)
        sleep(seconds: 0.5)
        await factory.destroy()
        factory = nil

        // Run 2: same clearOnInit, last clear was moments ago — cache must be preserved.
        let http2 = SecureHttpClientMock()
        http2.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cached_flag"], treatment: "from_network"))
        http2.fetchDelay = 2_000_000_000

        let cacheReady = expectation("SDK ready from cache without re-clear")
        factory2 = try buildFactory(httpClient: http2, target: target, prefix: prefix, rolloutCacheConfiguration: clearOnInit)
        factory2.client.addEventListener(TestEventListener(cacheExpectation: cacheReady))
        waitFor(cacheReady, timeout: 5)

        XCTAssertEqual(
            factory2.client.getTreatment("cached_flag").treatment, "persisted",
            "clearOnInit must not clear again within the 1-day protection window"
        )
        XCTAssertNotEqual(factory2.client.getTreatment("cached_flag").treatment, "from_network")
    }
}
