import XCTest
import Http
@testable import SplitThin

final class AuthE2ETest: XCTestCase {

    private var httpMock: RetryableHttpClientMock!
    private var factory: SplitFactory!

    private var prefix: String! // Unique per test method so each test gets its
                                // own CoreData DB, and they don't pollute each other.

    override func setUp() {
        super.setUp()
        httpMock = RetryableHttpClientMock()
        prefix = "test_\(UUID().uuidString.prefix(8))"
    }

    override func tearDown() async throws {
        await factory?.destroy()
        factory = nil
        httpMock = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    func testAuthSuccessAllowsEvaluationFetch() async throws {
        httpMock.responses = [
            HttpResponse(code: 200, data: Self.mockAuthResponse()),
            HttpResponse(code: 200, data: mockEvaluationsData())
        ]

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .singleSync, prefix: prefix)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let client = factory.client
        let treatment = client.getTreatment("my_feature").treatment

        XCTAssertEqual(treatment, "on")
        XCTAssertEqual(httpMock.executeCalls.count, 2)
        XCTAssertEqual(httpMock.executeCalls[0].category, .auth)
        XCTAssertEqual(httpMock.executeCalls[1].category, .evaluations)
    }

    func testAuthFailureReturnsControlTreatment() async throws {
        httpMock.responses = [
            HttpResponse(code: 401, data: nil)
        ]

        let sdkTimedOut = expectation("SDK timed out")
        let listener = TestEventListener(timeoutExpectation: sdkTimedOut)
        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .singleSync, readyTimeout: 1, prefix: prefix)
        factory.client.addEventListener(listener)

        waitFor(sdkTimedOut)

        let client = factory.client
        let treatment = client.getTreatment("my_feature").treatment

        XCTAssertEqual(treatment, "control", "Should return control when auth fails")
    }

    func testAuth401DoesNotStartPolling() async throws {
        httpMock.responses = [
            HttpResponse(code: 401, data: nil)
        ]

        let sdkTimedOut = expectation("SDK timed out")
        let listener = TestEventListener(timeoutExpectation: sdkTimedOut)
        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .polling, refreshRate: 1, readyTimeout: 1, prefix: prefix)
        factory.client.addEventListener(listener)

        waitFor(sdkTimedOut)

        let callCountAfterTimeout = httpMock.executeCalls.count

        sleep(seconds: 1.5)

        let callCountLater = httpMock.executeCalls.count
        XCTAssertEqual(callCountAfterTimeout, callCountLater, "No polling should occur after auth 401")
    }

    func testAuthInvalidJsonReturnsControlTreatment() async throws {
        let invalidJson = "{ invalid json }".data(using: .utf8)
        httpMock.responses = [
            HttpResponse(code: 200, data: invalidJson)
        ]

        let sdkTimedOut = expectation("SDK timed out")
        let listener = TestEventListener(timeoutExpectation: sdkTimedOut)
        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .singleSync, readyTimeout: 1, prefix: prefix)
        factory.client.addEventListener(listener)

        waitFor(sdkTimedOut)

        let client = factory.client
        let treatment = client.getTreatment("my_feature").treatment

        XCTAssertEqual(treatment, "control", "Should return control when auth response is invalid JSON")
    }

    func testAuthMissingTokenReturnsControlTreatment() async throws {
        let missingToken = """
        {"pushEnabled": true}
        """.data(using: .utf8)
        httpMock.responses = [
            HttpResponse(code: 200, data: missingToken)
        ]

        let sdkTimedOut = expectation("SDK timed out")
        let listener = TestEventListener(timeoutExpectation: sdkTimedOut)
        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .singleSync, readyTimeout: 1, prefix: prefix)
        factory.client.addEventListener(listener)

        waitFor(sdkTimedOut)

        let client = factory.client
        let treatment = client.getTreatment("my_feature").treatment

        XCTAssertEqual(treatment, "control", "Should return control when auth response is missing token")
    }

    func testAuthNetworkErrorReturnsControlTreatment() async throws {
        httpMock.errorToThrow = RetryableHttpError.networkError(NSError(domain: "test", code: -1))

        let sdkTimedOut = expectation("SDK timed out")
        let listener = TestEventListener(timeoutExpectation: sdkTimedOut)
        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .singleSync, readyTimeout: 1, prefix: prefix)
        factory.client.addEventListener(listener)

        waitFor(sdkTimedOut)

        let client = factory.client
        let treatment = client.getTreatment("my_feature").treatment

        XCTAssertEqual(treatment, "control", "Should return control when network error occurs")
    }

    func testAuthTokenExpirationIsParsedCorrectly() async throws {
        let futureExp = Int(Date().timeIntervalSince1970) + 3600
        httpMock.responses = [
            HttpResponse(code: 200, data: Self.mockAuthResponse(exp: futureExp)),
            HttpResponse(code: 200, data: mockEvaluationsData()),
            HttpResponse(code: 200, data: mockEvaluationsData())
        ]

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .polling, refreshRate: 1, prefix: prefix)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let authCalls = httpMock.executeCalls.filter { $0.category == .auth }
        XCTAssertEqual(authCalls.count, 1, "Should reuse cached credential, not re-auth")
    }

    func testAuth401OnEvaluationTriggersReauth() async throws {
        let futureExp = Int(Date().timeIntervalSince1970) + 3600
        httpMock.responses = [
            HttpResponse(code: 200, data: Self.mockAuthResponse(exp: futureExp)),
            HttpResponse(code: 401, data: nil),
            HttpResponse(code: 200, data: Self.mockAuthResponse(exp: futureExp)),
            HttpResponse(code: 200, data: mockEvaluationsData())
        ]

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .singleSync, prefix: prefix)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let authCalls = httpMock.executeCalls.filter { $0.category == .auth }
        XCTAssertEqual(authCalls.count, 2, "Should re-auth after 401 on evaluations")
    }

    func testSetTargetRefreshesAuthForNewMatchingKey() async throws {
        httpMock.responses = [
            HttpResponse(code: 200, data: Self.mockAuthResponse()),
            HttpResponse(code: 200, data: mockEvaluationsData()),
            HttpResponse(code: 200, data: Self.mockAuthResponse()),
            HttpResponse(code: 200, data: mockEvaluationsData())
        ]

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .singleSync, target: Target(matchingKey: "user-1", trafficType: "user"), prefix: prefix)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)
        XCTAssertEqual(httpMock.executeCalls.filter { $0.category == .auth }.count, 1, "exactly one auth at init")

        factory.client.setTarget(target: Target(matchingKey: "user-2", trafficType: "user"))

        waitUntil(timeout: 3) { self.httpMock.executeCalls.filter { $0.category == .auth }.count == 2 }
        XCTAssertEqual(httpMock.executeCalls.filter { $0.category == .auth }.count, 2, "setTarget with a new matchingKey must trigger a fresh auth for it")
    }

    func testSlowAuthDoesNotBlockSDKInitialization() async throws {
        httpMock.delaySeconds = 10
        httpMock.responses = [
            HttpResponse(code: 200, data: Self.mockAuthResponse()),
            HttpResponse(code: 200, data: mockEvaluationsData())
        ]

        let startTime = Date()
        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .singleSync, prefix: prefix)

        let client = factory.client
        let treatment = client.getTreatment("my_feature").treatment

        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertEqual(treatment, "control", "Should return control while auth is pending")
        XCTAssertLessThan(elapsed, 2.0, "SDK initialization should not block on slow auth")
    }

    func testDestroyDuringPendingAuthDoesNotHang() async throws {
        httpMock.delaySeconds = 30
        httpMock.responses = [
            HttpResponse(code: 200, data: Self.mockAuthResponse())
        ]

        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .singleSync, prefix: prefix)

        let startTime = Date()
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertLessThan(elapsed, 2.0, "Destroy should not wait for pending auth request")
    }

    // MARK: - Push disabled fallback

    func testStreamingFallsBackToPollingWhenPushDisabled() async throws {
        httpMock.responses = [
            HttpResponse(code: 200, data: Self.mockAuthResponse()), // pushEnabled:false
            HttpResponse(code: 200, data: mockEvaluationsData())    // initial fetch
        ]

        let spy = ObserverSpy()
        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(retryableHttpClient: httpMock, syncMode: .streaming, refreshRate: 1, prefix: prefix, observer: spy)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)
        XCTAssertFalse(spy.notifiedEvents.contains(where: isPeriodicFetch), "No polling should happen before the push-disabled fallback")

        // After the streaming layer sees pushEnabled=false it must switch to polling.
        waitUntil(timeout: 5) { spy.notifiedEvents.contains(where: self.isPeriodicFetch) }
    }

    private func isPeriodicFetch(_ event: ObservableEvent) -> Bool {
        if case .evalFetchRequested(let reason) = event, case .periodic = reason { return true }
        return false
    }

    // MARK: - Helpers

    private func mockEvaluationsData() -> Data {
        return """
        {
            "evaluations": [
                {
                    "flag": "my_feature",
                    "treatment": "on",
                    "config": "config_value",
                    "sets": []
                }
            ]
        }
        """.data(using: .utf8)!
    }

    // static + internal so other E2E tests can reuse it
    static func mockAuthResponse(exp: Int? = nil) -> Data {
        let expiration = exp ?? Int(Date().timeIntervalSince1970) + 3600
        let header = base64UrlEncode("{\"alg\":\"HS256\",\"typ\":\"JWT\"}")
        let payload = base64UrlEncode("{\"exp\":\(expiration),\"sub\":\"user-123\"}")
        let signature = "mock_signature"
        let token = "\(header).\(payload).\(signature)"

        return """
        {"token": "\(token)", "pushEnabled": false}
        """.data(using: .utf8)!
    }

    static func base64UrlEncode(_ string: String) -> String {
        let data = string.data(using: .utf8)!
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                                         .replacingOccurrences(of: "/", with: "_")
                                         .replacingOccurrences(of: "=", with: "")
    }
}
