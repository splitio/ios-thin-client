import XCTest
import Http
@testable import SplitThin

final class AuthE2ETest: XCTestCase {

    private var httpMock: RetryableHttpClientMock!

    override func setUp() {
        super.setUp()
        httpMock = RetryableHttpClientMock()
    }

    override func tearDown() {
        httpMock = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testAuthSuccessAllowsEvaluationFetch() async throws {
        httpMock.responses = [
            HttpResponse(code: 200, data: mockAuthResponse()),
            HttpResponse(code: 200, data: mockEvaluationsData())
        ]

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(onReadyExpectation: sdkReady)
        let factory = try buildFactory(syncMode: .singleSync)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let client = factory.client
        let treatment = client.getTreatment(flag: "my_feature").treatment

        XCTAssertEqual(treatment, "on")
        XCTAssertEqual(httpMock.executeCalls.count, 2)
        XCTAssertEqual(httpMock.executeCalls[0].category, .auth)
        XCTAssertEqual(httpMock.executeCalls[1].category, .evaluations)

        await factory.destroy()
    }

    func testAuthFailureReturnsControlTreatment() async throws {
        httpMock.responses = [
            HttpResponse(code: 401, data: nil)
        ]

        let sdkTimedOut = expectation(description: "SDK timed out")
        let listener = TestEventListener(onTimedOutExpectation: sdkTimedOut)
        let factory = try buildFactory(syncMode: .singleSync, timeout: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkTimedOut)

        let client = factory.client
        let treatment = client.getTreatment(flag: "my_feature").treatment

        XCTAssertEqual(treatment, "control", "Should return control when auth fails")

        await factory.destroy()
    }

    func testAuthInvalidJsonReturnsControlTreatment() async throws {
        let invalidJson = "{ invalid json }".data(using: .utf8)
        httpMock.responses = [
            HttpResponse(code: 200, data: invalidJson)
        ]

        let sdkTimedOut = expectation(description: "SDK timed out")
        let listener = TestEventListener(onTimedOutExpectation: sdkTimedOut)
        let factory = try buildFactory(syncMode: .singleSync, timeout: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkTimedOut)

        let client = factory.client
        let treatment = client.getTreatment(flag: "my_feature").treatment

        XCTAssertEqual(treatment, "control", "Should return control when auth response is invalid JSON")

        await factory.destroy()
    }

    func testAuthMissingTokenReturnsControlTreatment() async throws {
        let missingToken = """
        {"pushEnabled": true}
        """.data(using: .utf8)
        httpMock.responses = [
            HttpResponse(code: 200, data: missingToken)
        ]

        let sdkTimedOut = expectation(description: "SDK timed out")
        let listener = TestEventListener(onTimedOutExpectation: sdkTimedOut)
        let factory = try buildFactory(syncMode: .singleSync, timeout: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkTimedOut)

        let client = factory.client
        let treatment = client.getTreatment(flag: "my_feature").treatment

        XCTAssertEqual(treatment, "control", "Should return control when auth response is missing token")

        await factory.destroy()
    }

    func testAuthNetworkErrorReturnsControlTreatment() async throws {
        httpMock.errorToThrow = RetryableHttpError.networkError(NSError(domain: "test", code: -1))

        let sdkTimedOut = expectation(description: "SDK timed out")
        let listener = TestEventListener(onTimedOutExpectation: sdkTimedOut)
        let factory = try buildFactory(syncMode: .singleSync, timeout: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkTimedOut)

        let client = factory.client
        let treatment = await client.getTreatment(flag: "my_feature").treatment

        XCTAssertEqual(treatment, "control", "Should return control when network error occurs")

        await factory.destroy()
    }

    func testAuthTokenExpirationIsParsedCorrectly() async throws {
        let futureExp = Int(Date().timeIntervalSince1970) + 3600
        httpMock.responses = [
            HttpResponse(code: 200, data: mockAuthResponse(exp: futureExp)),
            HttpResponse(code: 200, data: mockEvaluationsData()),
            HttpResponse(code: 200, data: mockEvaluationsData())
        ]

        let sdkReady = expectation(description: "SDK ready")
        let sdkUpdate = expectation(description: "SDK update")
        let listener = TestEventListener(onReadyExpectation: sdkReady, onUpdateExpectation: sdkUpdate)
        let factory = try buildFactory(syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady, sdkUpdate)

        let authCalls = httpMock.executeCalls.filter { $0.category == .auth }
        XCTAssertEqual(authCalls.count, 1, "Should reuse cached credential, not re-auth")

        await factory.destroy()
    }

    func testAuth401OnEvaluationTriggersReauth() async throws {
        let futureExp = Int(Date().timeIntervalSince1970) + 3600
        httpMock.responses = [
            HttpResponse(code: 200, data: mockAuthResponse(exp: futureExp)),
            HttpResponse(code: 401, data: nil),
            HttpResponse(code: 200, data: mockAuthResponse(exp: futureExp)),
            HttpResponse(code: 200, data: mockEvaluationsData())
        ]

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(onReadyExpectation: sdkReady)
        let factory = try buildFactory(syncMode: .singleSync)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let authCalls = httpMock.executeCalls.filter { $0.category == .auth }
        XCTAssertEqual(authCalls.count, 2, "Should re-auth after 401 on evaluations")

        await factory.destroy()
    }

    func testSlowAuthDoesNotBlockSDKInitialization() async throws {
        httpMock.delaySeconds = 10
        httpMock.responses = [
            HttpResponse(code: 200, data: mockAuthResponse()),
            HttpResponse(code: 200, data: mockEvaluationsData())
        ]

        let startTime = Date()
        let factory = try buildFactory(syncMode: .singleSync)

        let client = factory.client
        let treatment = client.getTreatment(flag: "my_feature").treatment

        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertEqual(treatment, "control", "Should return control while auth is pending")
        XCTAssertLessThan(elapsed, 2.0, "SDK initialization should not block on slow auth")

        await factory.destroy()
    }

    func testDestroyDuringPendingAuthDoesNotHang() async throws {
        httpMock.delaySeconds = 30
        httpMock.responses = [
            HttpResponse(code: 200, data: mockAuthResponse())
        ]

        let factory = try buildFactory(syncMode: .singleSync)

        let startTime = Date()
        await factory.destroy()
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertLessThan(elapsed, 2.0, "Destroy should not wait for pending auth request")
    }

    // MARK: - Helpers

    private func buildFactory(syncMode: SyncMode, refreshRate: Int = 1, timeout: Int = -1) throws -> SplitFactory {
        let config = SplitClientConfig.builder()
                                      .setMinEvaluationRefreshRate(1)
                                      .set(syncMode: syncMode)
                                      .set(evaluationRefreshRate: refreshRate)
                                      .set(timeout: timeout)
                                      .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setRetryableHttpClient(httpMock)

        guard let factory = builder.setSdkKey(SdkKey("test-sdk-key"))
                                   .setTarget(Target(matchingKey: "user-123"))
                                   .setConfig(config)
                                   .build() else {
            throw NSError(domain: "AuthE2ETest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to build factory"])
        }

        return factory
    }

    private func mockAuthResponse(exp: Int? = nil) -> Data {
        let expiration = exp ?? Int(Date().timeIntervalSince1970) + 3600
        let header = base64UrlEncode("{\"alg\":\"HS256\",\"typ\":\"JWT\"}")
        let payload = base64UrlEncode("{\"exp\":\(expiration),\"sub\":\"user-123\"}")
        let signature = "mock_signature"
        let token = "\(header).\(payload).\(signature)"

        return """
        {"token": "\(token)", "pushEnabled": false}
        """.data(using: .utf8)!
    }

    private func mockEvaluationsData() -> Data {
        return """
        {
            "evaluations": [
                {
                    "featureName": "my_feature",
                    "treatment": "on",
                    "config": "config_value",
                    "sets": []
                }
            ]
        }
        """.data(using: .utf8)!
    }

    private func base64UrlEncode(_ string: String) -> String {
        let data = string.data(using: .utf8)!
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                                         .replacingOccurrences(of: "/", with: "_")
                                         .replacingOccurrences(of: "=", with: "")
    }
}
