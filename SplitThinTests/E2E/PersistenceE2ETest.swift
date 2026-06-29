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

    func testPersistedEvaluationChangeNumberRehydrates() async throws {
        let prefix = "persist_e2e_cn_\(UUID().uuidString.prefix(8))"
        let target = Target(matchingKey: "user_cn", trafficType: "user")
        let persistedCN: Int64 = 7777
        let networkCN: Int64 = 8888 // distinct from the persisted value so disk vs network is unambiguous

        // Run 1: persist cn_flag with per-evaluation changeNumber = persistedCN.
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cn_flag"], till: persistedCN))
        let sdkReady = expectation("SDK ready")
        factory = try buildFactory(httpClient: httpMock, target: target, prefix: prefix)
        factory.client.addEventListener(TestEventListener(readyExpectation: sdkReady))
        waitFor(sdkReady)
        XCTAssertEqual(factory.client.getTreatment("cn_flag").changeNumber, persistedCN)

        sleep(seconds: 0.5) // let persistence write (non-blocking)
        await factory.destroy()
        factory = nil

        // Run 2: the network returns a *different* changeNumber, held in flight behind a long delay.
        // We gate on SDK_READY_FROM_CACHE: at that point only the disk load can have populated the cache
        // (the network hasn't responded yet), so the value served proves it was rehydrated from storage.
        let httpMock2 = SecureHttpClientMock()
        httpMock2.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["cn_flag"], till: networkCN))
        httpMock2.fetchDelay = 2_000_000_000 // 2s: keep the network fetch in flight while we assert the disk value

        let cacheReady = expectation("SDK ready from cache")
        factory2 = try buildFactory(httpClient: httpMock2, target: target, prefix: prefix)
        factory2.client.addEventListener(TestEventListener(cacheExpectation: cacheReady))
        waitFor(cacheReady, timeout: 5)

        let hydrated = factory2.client.getTreatment("cn_flag")
        XCTAssertEqual(hydrated.changeNumber, persistedCN, "changeNumber must be rehydrated from persisted storage")
        XCTAssertNotEqual(hydrated.changeNumber, networkCN, "the in-flight network changeNumber must not be served yet")

        // Once the network fetch lands, the fresh changeNumber takes over (proving run 2 actually hit the network).
        waitUntil(timeout: 4) { self.factory2.client.getTreatment("cn_flag").changeNumber == networkCN }
        XCTAssertEqual(factory2.client.getTreatment("cn_flag").changeNumber, networkCN, "after the fetch lands, the fresh network changeNumber takes over")
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

    func testWarmStartUpToDateResponseKeepsPersistedCache() async throws {
        let prefix = "persist_e2e_uptodate_\(UUID().uuidString.prefix(8))"
        let target = Target(matchingKey: "user_a", trafficType: "user")

        // Run 1: full sync persists my_flag at changeNumber 1000.
        let server1 = SinceAwareHttpClientMock(
            authData: AuthE2ETest.mockAuthResponse(),
            fullSyncData: mockEvaluationsData(flags: ["my_flag"], till: 1000),
            upToDateData: mockEvaluationsData(flags: [], since: 1000, till: 1000)
        )
        let sdkReady = expectation("SDK ready")
        factory = try buildFactory(retryableHttpClient: server1, target: target, prefix: prefix)
        factory.client.addEventListener(TestEventListener(readyExpectation: sdkReady))
        waitFor(sdkReady)
        XCTAssertEqual(factory.client.getTreatment("my_flag").treatment, "on")

        sleep(seconds: 0.5) // let persistence write (non-blocking)
        await factory.destroy()
        factory = nil

        // Run 2: same key, cache still valid. The SDK sends since=1000 and the server replies
        // "up to date" with an empty payload. That empty response must NOT wipe the hydrated cache.
        let server2 = SinceAwareHttpClientMock(
            authData: AuthE2ETest.mockAuthResponse(),
            fullSyncData: mockEvaluationsData(flags: ["my_flag"], till: 1000),
            upToDateData: mockEvaluationsData(flags: [], since: 1000, till: 1000),
            evaluationsDelay: 0.3 // let the empty fetch land and be processed before asserting
        )
        let sdkReady2 = expectation("SDK ready 2")
        factory2 = try buildFactory(retryableHttpClient: server2, target: target, prefix: prefix)
        factory2.client.addEventListener(TestEventListener(readyExpectation: sdkReady2))
        waitFor(sdkReady2, timeout: 5)

        sleep(seconds: 0.5) // ensure the up-to-date fetch has landed
        XCTAssertEqual(
            factory2.client.getTreatment("my_flag").treatment, "on",
            "An up-to-date (empty) warm-start response must not wipe the persisted cache"
        )
    }

    func testSetTargetHydratesPersistedCacheForNewTarget() async throws {
        let prefix = "persist_e2e_settarget_\(UUID().uuidString.prefix(8))"

        // Prior session: persist flag_b = "b_cached" for user-B at changeNumber 1000.
        let httpB = SecureHttpClientMock()
        httpB.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_b"], treatment: "b_cached", till: 1000))
        let readyB = expectation("SDK ready B")
        factory = try buildFactory(httpClient: httpB, target: Target(matchingKey: "user-B", trafficType: "user"), prefix: prefix)
        factory.client.addEventListener(TestEventListener(readyExpectation: readyB))
        waitFor(readyB)
        sleep(seconds: 0.5) // let persistence write (non-blocking)
        await factory.destroy()
        factory = nil

        // New session: start on user-A, then switch to user-B. Every treatment is distinct so no value
        // can coincide and mask a bug:
        //   user-A flag_a           -> "a_treatment"
        //   user-B persisted (disk) -> "b_cached"
        //   user-B network (fetch)  -> "b_network"  (changeNumber 1001, behind a 1s delay)
        let http = SecureHttpClientMock()
        http.fetchEvaluationsResultByKey["user-A"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"], treatment: "a_treatment")))
        http.fetchEvaluationsResultByKey["user-B"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_b"], treatment: "b_network", till: 1001)))
        http.fetchDelay = 1_000_000_000 // 1s: keep the user-B fetch in flight

        let readyA = expectation("SDK ready A")
        factory2 = try buildFactory(httpClient: http, target: Target(matchingKey: "user-A", trafficType: "user"), prefix: prefix)
        factory2.client.addEventListener(TestEventListener(readyExpectation: readyA))
        waitFor(readyA, timeout: 5)

        factory2.client.setTarget(target: Target(matchingKey: "user-B", trafficType: "user"))

        // Hydration is async: wait until it lands (flag_b stops being control). The network fetch is
        // still in flight behind the 1s delay, so the value now must be the persisted "b_cached" and
        // must NOT yet be the pending network "b_network".
        waitUntil(timeout: 0.6) { self.factory2.client.getTreatment("flag_b").treatment != "control" }
        let inFlight = factory2.client.getTreatment("flag_b").treatment
        XCTAssertEqual(inFlight, "b_cached", "setTarget must serve the persisted cache via hydration during the in-flight window")
        XCTAssertNotEqual(inFlight, "b_network", "the pending network value must not be served while its fetch is still in flight")

        // Once the fetch lands, the fresh network value takes over.
        waitUntil(timeout: 3) { self.factory2.client.getTreatment("flag_b").treatment == "b_network" }
        XCTAssertEqual(factory2.client.getTreatment("flag_b").treatment, "b_network", "after the fetch lands, the fresh network value takes over")
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
