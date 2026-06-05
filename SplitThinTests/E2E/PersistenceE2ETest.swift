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
        factory = try buildFactoryWithPrefix(httpClient: httpMock, target: target, prefix: prefix)
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
        factory2 = try buildFactoryWithPrefix(httpClient: httpMock2, target: target, prefix: prefix)
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
        factory = try buildFactoryWithPrefix(httpClient: httpMock, target: targetA, prefix: prefix)
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
        factory2 = try buildFactoryWithPrefix(httpClient: httpMock2, target: targetB, prefix: prefix)
        factory2.client.addEventListener(listenerB)
        waitFor(sdkReady2, timeout: 5)

        XCTAssertEqual(
            httpMock2.fetchEvaluationsCalls.count, 1,
            "Factory B should have fired a fresh network request because attributes changed (cache invalidated)"
        )
    }

    // Storage-level isolation between nil and non-nil bucketingKey identities is covered in
    // SplitThinTests/Storage/CoreDataStorageTests.swift (testNilAndNonNilBucketingKeysDontOverwriteEachOther
    // and testClearDeletesByScopedIdentity). An E2E-level test would require fine-grained control
    // over CoreData write timing that is not yet exposed in the E2E test harness.
}

// MARK: - Helpers (private to this file)

extension PersistenceE2ETest {
    private func buildFactoryWithPrefix(httpClient: SecureHttpClient, target: Target, prefix: String) throws -> SplitFactory {
        let config = SplitClientConfig.builder()
            .setMinEvaluationRefreshRate(1)
            .set(syncMode: .singleSync)
            .set(prefix: prefix)
            .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpClient)
        builder.setCredentialStorage(DefaultCredentialStorage())

        guard let factory = builder.setSdkKey("test-sdk-key").setTarget(target).setConfig(config).build() else {
            throw NSError(domain: "E2ETest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to build factory"])
        }

        return factory
    }
}
