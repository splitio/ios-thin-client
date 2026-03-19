import XCTest
import Http
@testable import SplitThin

final class PollingE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!

    override func setUp() {
        super.setUp()
        httpMock = SecureHttpClientMock()
        SplitClientConfig.setMinEvaluationRefreshRate(1)
    }

    override func tearDown() {
        httpMock = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testPollingFetchesPeriodically() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData())

        let factory = try buildFactory(syncMode: .polling, refreshRate: 1)

        try await Task.sleep(nanoseconds: 2_500_000_000)

        let callCount = httpMock.fetchEvaluationsCalls.count
        XCTAssertGreaterThanOrEqual(callCount, 2, "Expected at least 2 fetches, got \(callCount)")

        await factory.destroy()
    }

    func testPollingUpdatesClientTreatments() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData())

        let factory = try buildFactory(syncMode: .polling, refreshRate: 1)

        try await Task.sleep(nanoseconds: 500_000_000)

        let result = factory.client.getTreatment(flag: "my-flag", evaluationOptions: nil)
        XCTAssertEqual(result.treatment, "on")

        await factory.destroy()
    }

    func testPollingStopsOnDestroy() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData())

        let factory = try buildFactory(syncMode: .polling, refreshRate: 1)

        try await Task.sleep(nanoseconds: 500_000_000)
        await factory.destroy()

        let callCountAfterDestroy = httpMock.fetchEvaluationsCalls.count

        try await Task.sleep(nanoseconds: 500_000_000)

        let callCountLater = httpMock.fetchEvaluationsCalls.count
        XCTAssertEqual(callCountAfterDestroy, callCountLater, "No more fetches should occur after destroy")
    }

    func testSingleSyncOnlyFetchesOnce() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData())

        let factory = try buildFactory(syncMode: .singleSync, refreshRate: 1)

        try await Task.sleep(nanoseconds: 500_000_000)

        let callCount = httpMock.fetchEvaluationsCalls.count
        XCTAssertEqual(callCount, 1, "SingleSync should fetch exactly once, got \(callCount)")

        await factory.destroy()
    }

    // MARK: - Helpers

    private func buildFactory(syncMode: SyncMode, refreshRate: Int) throws -> SplitFactory {
        let config = SplitClientConfig.builder()
                                      .set(syncMode: syncMode)
                                      .set(evaluationRefreshRate: refreshRate)
                                      .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpMock)
        
        guard let factory = builder.setSdkKey(SdkKey("test-sdk-key"))
                                   .setTarget(Target(matchingKey: "user-123"))
                                   .setConfig(config)
                                   .build() else {
            throw NSError(domain: "PollingE2ETest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to build factory"])
        }

        return factory
    }

    private func mockEvaluationsData() -> Data {
        let json = """
        {
            "evaluations": [
                {
                    "featureName": "my-flag",
                    "treatment": "on",
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
