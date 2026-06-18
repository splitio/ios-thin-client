import XCTest
import Http
@testable import SplitThin

final class FetchCoordinatorE2ETest: XCTestCase {

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

    // MARK: - Multi-target Tests

    func testDifferentTargetsExecuteSeparateFetches() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))
        httpMock.fetchDelay = 10_000_000 // 10ms

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        factory.client.setTarget(target: Target(matchingKey: "user-A", trafficType: "user"))
        factory.client.setTarget(target: Target(matchingKey: "user-B", trafficType: "user"))

        waitFor(sdkReady)

        let uniqueTargets = Set(httpMock.fetchEvaluationsCalls.map { $0.target.matchingKey })
        XCTAssertTrue(uniqueTargets.contains("user-A"), "Should have fetched for user-A")
        XCTAssertTrue(uniqueTargets.contains("user-B"), "Should have fetched for user-B")

    }

    // MARK: - setTarget Tests

    func testSetTargetTriggersFetch() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))
        httpMock.fetchDelay = 20_000_000 // 20ms

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        factory.client.setTarget(target: Target(matchingKey: "new-user", trafficType: "user"))

        waitFor(sdkReady)

        let fetchesForNewUser = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "new-user" }.count
        XCTAssertEqual(fetchesForNewUser, 1, "Should have fetched for new-user")

    }

    func testSetTargetSwitchesEvaluation() async throws {
        httpMock.fetchEvaluationsResultByKey["user-1"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"], treatment: "on")))
        httpMock.fetchEvaluationsResultByKey["user-2"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"], treatment: "off", till: 12346)))
        httpMock.fetchDelay = 300_000_000 // 0.3s: keeps user-2's fetch in flight so we can observe the control window

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, target: Target(matchingKey: "user-1", trafficType: "user"))
        factory.client.addEventListener(listener)

        waitFor(sdkReady, timeout: 5)
        XCTAssertEqual(factory.client.getTreatment("flag_a").treatment, "on")

        factory.client.setTarget(target: Target(matchingKey: "user-2", trafficType: "user"))

        // Check that the evaluation is CONTROL, until the new target's fetch lands. 
        let deadline = Date().addingTimeInterval(3)
        var treatment = factory.client.getTreatment("flag_a").treatment
        while treatment != "off" && Date() < deadline {
            XCTAssertEqual(treatment, "control", "While the new target's fetch is in flight, the flag must be control, not the previous target's value")
            sleep(seconds: 0.05)
            treatment = factory.client.getTreatment("flag_a").treatment
        }

        // Then it changes to OFF.
        XCTAssertEqual(treatment, "off", "getTreatment should reflect the new target after setTarget")
        XCTAssertTrue(httpMock.fetchEvaluationsCalls.contains { $0.target.matchingKey == "user-2" }, "evaluations should be fetched for the new target")
    }

    func testSetTargetTriggersNewFetchForSameTarget() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))
        httpMock.fetchDelay = 10_000_000 // 10ms

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        factory.client.setTarget(target: Target(matchingKey: "user-A", trafficType: "user"))
        sleep(seconds: 0.03) // Give time for setTarget fetch
        factory.client.setTarget(target: Target(matchingKey: "user-A", trafficType: "user"))
        sleep(seconds: 0.03) // Give time for second setTarget fetch

        let fetchesForUserA = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "user-A" }.count
        XCTAssertEqual(fetchesForUserA, 2, "Sequential setTarget calls should each trigger a fetch")

    }

    // MARK: - Initial fetch Tests

    func testGetTreatmentAfterInitialFetch() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))
        httpMock.fetchDelay = 20_000_000 // 20ms

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let result = factory.client.getTreatment("my-flag")
        XCTAssertEqual(result.treatment, "on", "getTreatment should return fetched value after initial fetch completes")

    }

    func testPollingModeExecutesMultipleFetches() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)
        
        sleep(seconds: 3)

        let callCount = httpMock.fetchEvaluationsCalls.count
        XCTAssertGreaterThanOrEqual(callCount, 2, "Polling should execute multiple fetches, got \(callCount)")
    }
}
