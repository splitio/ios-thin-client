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

    func testSetTargetFiresUpdateWhenNewData() async throws {
        httpMock.fetchEvaluationsResultByKey["user-1"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"], treatment: "on", till: 100)))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, target: Target(matchingKey: "user-1", trafficType: "user"))
        factory.client.addEventListener(listener)

        waitFor(sdkReady)
        XCTAssertEqual(listener.onUpdateCallCount, 0, "No update before any data change")

        // The server now returns different data for the same key (e.g., attribute-based targeting changed).
        httpMock.fetchEvaluationsResultByKey["user-1"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"], treatment: "off", till: 200)))

        // Same matchingKey, different attributes: same cache key
        factory.client.setTarget(target: Target(matchingKey: "user-1", attributes: ["env": "staging"], trafficType: "user"))
        waitUntil(timeout: 3) { listener.onUpdateCallCount == 1 }

        XCTAssertEqual(factory.client.getTreatment("flag_a").treatment, "off", "The new data must be served")

        // No periodic sync in single-sync mode
        sleep(seconds: 2)
        XCTAssertEqual(listener.onUpdateCallCount, 1, "Without a setTarget, no periodic sync should fire an update")

        // A second setTarget with fresh data must fire SDK_UPDATE again, confirming the update is driven by setTarget.
        httpMock.fetchEvaluationsResultByKey["user-1"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"], treatment: "on", till: 300)))
        factory.client.setTarget(target: Target(matchingKey: "user-1", attributes: ["env": "prod"], trafficType: "user"))
        waitUntil(timeout: 3) { listener.onUpdateCallCount == 2 }
        
        XCTAssertEqual(factory.client.getTreatment("flag_a").treatment, "on", "The latest target's data must be served")
    }

    func testSetTargetToDifferentKeyFiresUpdate() async throws {
        httpMock.fetchEvaluationsResultByKey["user-1"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"], treatment: "on", till: 100)))
        httpMock.fetchEvaluationsResultByKey["user-2"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"], treatment: "off", till: 200)))
        httpMock.fetchEvaluationsResultByKey["user-3"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"], treatment: "v3", till: 300)))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, target: Target(matchingKey: "user-1", trafficType: "user"))
        factory.client.addEventListener(listener)

        waitFor(sdkReady)
        XCTAssertEqual(listener.onUpdateCallCount, 0, "No update before any data change")

        factory.client.setTarget(target: Target(matchingKey: "user-2", trafficType: "user"))
        waitUntil(timeout: 3) { listener.onUpdateCallCount == 1 }

        XCTAssertEqual(factory.client.getTreatment("flag_a").treatment, "off", "The new key's data must be served")

        factory.client.setTarget(target: Target(matchingKey: "user-3", trafficType: "user"))
        waitUntil(timeout: 3) { listener.onUpdateCallCount == 2 }

        XCTAssertEqual(factory.client.getTreatment("flag_a").treatment, "v3", "The latest key's data must be served")
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
