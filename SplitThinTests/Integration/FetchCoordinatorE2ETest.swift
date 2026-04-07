import XCTest
import Http
@testable import SplitThin

final class FetchCoordinatorE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!

    override func setUp() {
        super.setUp()
        httpMock = SecureHttpClientMock()
    }

    override func tearDown() {
        httpMock = nil
        super.tearDown()
    }

    // MARK: - Multi-target Tests

    func testDifferentTargetsExecuteSeparateFetches() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData())
        httpMock.fetchDelay = 10_000_000 // 10ms

        let factory = try buildFactory()

        factory.client.setTarget(target: Target(matchingKey: "user-A"))
        factory.client.setTarget(target: Target(matchingKey: "user-B"))

        // Wait for async fetches to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let uniqueTargets = Set(httpMock.fetchEvaluationsCalls.map { $0.target.matchingKey })
        XCTAssertTrue(uniqueTargets.contains("user-A"), "Should have fetched for user-A")
        XCTAssertTrue(uniqueTargets.contains("user-B"), "Should have fetched for user-B")

        await factory.destroy()
    }

    // MARK: - setTarget Tests

    func testSetTargetTriggersFetch() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(treatment: "variant-X"))
        httpMock.fetchDelay = 20_000_000 // 20ms

        let factory = try buildFactory()

        factory.client.setTarget(target: Target(matchingKey: "new-user"))

        // Wait for async fetch to complete
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        let fetchesForNewUser = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "new-user" }.count
        XCTAssertEqual(fetchesForNewUser, 1, "Should have fetched for new-user")

        await factory.destroy()
    }

    func testSetTargetTriggersNewFetchForSameTarget() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData())
        httpMock.fetchDelay = 10_000_000 // 10ms

        let factory = try buildFactory()

        factory.client.setTarget(target: Target(matchingKey: "user-A"))
        // Wait for first fetch to complete before triggering second
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms
        factory.client.setTarget(target: Target(matchingKey: "user-A"))
        // Wait for second fetch
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms

        let fetchesForUserA = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "user-A" }.count
        XCTAssertEqual(fetchesForUserA, 2, "Sequential setTarget calls should each trigger a fetch")

        await factory.destroy()
    }

    // MARK: - Initial fetch Tests

    func testGetTreatmentAfterInitialFetch() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(treatment: "fetched-value"))
        httpMock.fetchDelay = 20_000_000 // 20ms

        let factory = try buildFactory()
        
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms - wait for initial fetch

        let result = factory.client.getTreatment(flag: "my-flag")
        XCTAssertEqual(result.treatment, "fetched-value", "getTreatment should return fetched value after initial fetch completes")

        await factory.destroy()
    }

    func testPollingModeExecutesMultipleFetches() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData())

        let factory = try buildFactory(syncMode: .polling, refreshRate: 1)

        try await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s - enough for initial + 1 poll

        let callCount = httpMock.fetchEvaluationsCalls.count
        XCTAssertGreaterThanOrEqual(callCount, 2, "Polling should execute multiple fetches, got \(callCount)")

        await factory.destroy()
    }

    // MARK: - Helpers

    private func buildFactory(syncMode: SyncMode = .singleSync, refreshRate: Int = 1) throws -> SplitFactory {
        let config = SplitClientConfig.builder()
            .setMinEvaluationRefreshRate(1)
            .set(syncMode: syncMode)
            .set(evaluationRefreshRate: refreshRate)
            .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpMock)

        guard let factory = builder.setSdkKey(SdkKey("test-sdk-key"))
            .setTarget(Target(matchingKey: "initial-user"))
            .setConfig(config)
            .build() else {
            throw NSError(domain: "FetchCoordinatorE2ETest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to build factory"])
        }

        return factory
    }

    private func mockEvaluationsData(treatment: String = "on") -> Data {
        let json = """
        {
            "evaluations": [
                {
                    "featureName": "my-flag",
                    "treatment": "\(treatment)",
                    "label": "default rule",
                    "changeNumber": 12345,
                    "sets": ["set-a"]
                }
            ],
            "since": -1,
            "till": 12345
        }
        """
        return json.data(using: .utf8)!
    }
}
