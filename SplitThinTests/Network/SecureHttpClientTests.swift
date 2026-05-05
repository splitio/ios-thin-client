import XCTest
import Http
@testable import SplitThin

final class DefaultSecureHttpClientTest: XCTestCase {

    private var retryableHttpMock: RetryableHttpClientMock!
    private var authProviderMock: AuthProviderMock!
    private var serviceEndpoints: ServiceEndpoints!
    private var client: DefaultSecureHttpClient!

    override func setUp() {
        super.setUp()
        retryableHttpMock = RetryableHttpClientMock()
        authProviderMock = AuthProviderMock()
        authProviderMock.credentialToReturn = makeCredential()
        serviceEndpoints = ServiceEndpoints.builder().set(sdkEndpoint: "https://evaluator.split.io/api").set(eventsEndpoint: "https://events.split.io/api").set(telemetryServiceEndpoint: "https://telemetry.split.io/api/v1").build()
        client = DefaultSecureHttpClient(retryableHttpClient: retryableHttpMock, authProvider: authProviderMock, serviceEndpoints: serviceEndpoints)
    }

    // MARK: - fetchEvaluations

    func testFetchEvaluationsUsesAuthToken() async throws {
        authProviderMock.credentialToReturn = makeCredential(token: "jwt-token")
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1")

        try await client.fetchEvaluations(target: target)

        XCTAssertEqual(authProviderMock.getCredentialCallCount, 1)
        XCTAssertEqual(authProviderMock.lastTargetRequested, "user1")

        let endpoint = retryableHttpMock.executeCalls[0].endpoint
        XCTAssertEqual(endpoint.headers["Authorization"], "Bearer jwt-token")
    }

    func testFetchEvaluationsIncludesUserQueryParam() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "lucrap")

        try await client.fetchEvaluations(target: target)

        let url = retryableHttpMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertTrue(url.contains("user=lucrap"), "URL should contain user param: \(url)")
        XCTAssertTrue(url.contains("since=-1"), "URL should contain since param: \(url)")
    }

    func testFetchEvaluationsIncludesFlagNames() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1")
        let filters = EvaluationFilters(flagNames: ["flag1", "flag2"])

        _ = try await client.fetchEvaluations(target: target, filters: filters)

        let url = retryableHttpMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertTrue(url.contains("names=flag1,flag2"), "URL should contain names param: \(url)")
    }

    func testFetchEvaluationsIncludesFlagSets() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1")
        let filters = EvaluationFilters(flagSets: ["setA", "setB"])

        _ = try await client.fetchEvaluations(target: target, filters: filters)

        let url = retryableHttpMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertTrue(url.contains("sets=setA,setB"), "URL should contain sets param: \(url)")
    }

    func testFetchEvaluationsSendsEmptyBodyWhenNoAttributes() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1")

        try await client.fetchEvaluations(target: target)

        let body = retryableHttpMock.executeCalls[0].body
        XCTAssertEqual(body, "{}".data(using: .utf8))
    }

    func testFetchEvaluationsSendsAttributesInBody() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1", attributes: ["plan": "enterprise", "role": "admin"])

        try await client.fetchEvaluations(target: target)

        let body = retryableHttpMock.executeCalls[0].body!
        let parsed = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertEqual(parsed["plan"] as? String, "enterprise")
        XCTAssertEqual(parsed["role"] as? String, "admin")
    }

    func testFetchEvaluationsIncludesContentDigestHeader() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "Mauro", attributes: ["city": "mdp", "age": 150])

        try await client.fetchEvaluations(target: target)

        let endpoint = retryableHttpMock.executeCalls[0].endpoint
        XCTAssertEqual(endpoint.headers["X-Harness-FME-Content-Digest"], "EVu1Yxs6Jvs")
    }

    func testFetchEvaluationsUsesEvaluationsCategory() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: Data())]

        let target = Target(matchingKey: "user1")

        try await client.fetchEvaluations(target: target)

        XCTAssertEqual(retryableHttpMock.executeCalls[0].category, .evaluations)
    }

    // MARK: - 401 Retry Flow

    func testFetchEvaluationsRetriesOn401() async throws {
        authProviderMock.credentialToReturn = makeCredential(token: "stale-token")

        retryableHttpMock.responses = [
            HttpResponse(code: 401, data: nil),
            HttpResponse(code: 200, data: Data())
        ]

        let target = Target(matchingKey: "user1")

        try await client.fetchEvaluations(target: target)

        XCTAssertEqual(authProviderMock.invalidateCallCount, 1)
        XCTAssertEqual(authProviderMock.lastTargetInvalidated, "user1")
        XCTAssertEqual(authProviderMock.getCredentialCallCount, 2)
        XCTAssertEqual(retryableHttpMock.executeCalls.count, 2)
    }

    func testFetchEvaluationsReturns401OnSecondFailure() async throws {
        authProviderMock.credentialToReturn = makeCredential(token: "bad-token")

        retryableHttpMock.responses = [
            HttpResponse(code: 401, data: nil),
            HttpResponse(code: 401, data: nil)
        ]

        let target = Target(matchingKey: "user1")

        let response = try await client.fetchEvaluations(target: target)

        XCTAssertEqual(response.code, 401)
        XCTAssertEqual(retryableHttpMock.executeCalls.count, 2)
    }

    func testFetchEvaluationsDoesNotRetryOnNon401Error() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 500, data: nil)]

        let target = Target(matchingKey: "user1")

        let response = try await client.fetchEvaluations(target: target)

        XCTAssertEqual(response.code, 500)
        XCTAssertEqual(authProviderMock.invalidateCallCount, 0)
        XCTAssertEqual(retryableHttpMock.executeCalls.count, 1)
    }

    // MARK: - postEvents & postTelemetry

    func testPostEventsUsesEventsCategory() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 202, data: nil)]

        let payload = "{}".data(using: .utf8)!

        let response = try await client.postEvents(payload: payload)

        XCTAssertEqual(response.code, 202)
        XCTAssertEqual(retryableHttpMock.executeCalls[0].category, .events)
        XCTAssertEqual(retryableHttpMock.executeCalls[0].body, payload)
    }

    func testPostTelemetryUsesTelemetryCategory() async throws {
        retryableHttpMock.responses = [HttpResponse(code: 200, data: nil)]

        let payload = "{}".data(using: .utf8)!

        let response = try await client.postTelemetry(payload: payload)

        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(retryableHttpMock.executeCalls[0].category, .telemetry)
    }

    // MARK: - Helpers
    private func makeCredential(token: String = "test-token") -> JwtCredential {
        JwtCredential(token: token, expiresAt: Date().addingTimeInterval(3600), pushEnabled: true)
    }
}
