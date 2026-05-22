import XCTest
import Http
@testable import SplitThin

final class DefaultCredentialFetcherTest: XCTestCase {

    private var httpClientMock: RetryableHttpClientMock!
    private var fetcher: DefaultCredentialFetcher!
    private let authEndpoint = URL(string: "https://auth.split.io/api/v3")!
    private let sdkKey = "test-sdk-key"

    override func setUp() {
        super.setUp()
        httpClientMock = RetryableHttpClientMock()
        fetcher = DefaultCredentialFetcher(retryableHttpClient: httpClientMock, observer: ObserverSpy(), authEndpoint: authEndpoint, sdkKey: sdkKey)
    }

    func testFetchCredentialSuccess() async throws {
        let jwt = makeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let authResponse = """
        {"token":"\(jwt)","pushEnabled":true,"connDelay":1}
        """.data(using: .utf8)!

        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        let credential = try await fetcher.fetchCredential(for: ["user1"])

        XCTAssertEqual(credential.token, jwt)
        XCTAssertTrue(credential.pushEnabled)
        XCTAssertTrue(credential.expiresAt > Date())
    }

    func testFetchCredentialSendsCorrectRequest() async throws {
        let jwt = makeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let authResponse = """
        {"token":"\(jwt)","pushEnabled":false}
        """.data(using: .utf8)!

        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        try await fetcher.fetchCredential(for: "user1")

        XCTAssertEqual(httpClientMock.executeCalls.count, 1)

        let call = httpClientMock.executeCalls[0]
        XCTAssertEqual(call.category, .auth)
        XCTAssertTrue(call.endpoint.url.absoluteString.contains("/auth"))
        XCTAssertTrue(call.endpoint.url.absoluteString.contains("users=user1"))
        XCTAssertEqual(call.endpoint.headers["Authorization"], "Bearer \(sdkKey)")
    }

    func testFetchCredentialWithMultipleUsers() async throws {
        let jwt = makeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let authResponse = """
        {"token":"\(jwt)","pushEnabled":true}
        """.data(using: .utf8)!

        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        _ = try await fetcher.fetchCredential(for: ["user1", "user2"])

        let url = httpClientMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertTrue(url.contains("users=user1,user2"))
    }

    func testThrowsUnauthorizedOn401() async throws {
        httpClientMock.responses = [HttpResponse(code: 401, data: nil)]

        do {
            try await fetcher.fetchCredential(for: "user1")
            XCTFail("Expected unauthorized error")
        } catch CredentialFetcherError.unauthorized {
            // Expected
        } catch {
            XCTFail("Expected .unauthorized, got: \(error)")
        }
    }

    func testThrowsInvalidAuthResponseOnNon200() async throws {
        httpClientMock.responses = [HttpResponse(code: 500, data: nil)]

        do {
            try await fetcher.fetchCredential(for: "user1")
            XCTFail("Expected error")
        } catch CredentialFetcherError.invalidAuthResponse {
            // Expected
        } catch {
            XCTFail("Expected .invalidAuthResponse, got: \(error)")
        }
    }

    func testFetchCredentialThrowsOnNilData() async throws {
        httpClientMock.responses = [HttpResponse(code: 200, data: nil)]

        do {
            try await fetcher.fetchCredential(for: "user1")
            XCTFail("Expected error")
        } catch is CredentialFetcherError {
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchCredentialThrowsOnInvalidJwt() async throws {
        let authResponse = """
        {"token":"not-a-jwt","pushEnabled":true}
        """.data(using: .utf8)!

        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        do {
            try await fetcher.fetchCredential(for: "user1")
            XCTFail("Expected error")
        } catch is CredentialFetcherError {
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchCredentialParsesExpirationCorrectly() async throws {
        let expTime: TimeInterval = 1773333499
        let jwt = makeJwt(exp: expTime)
        let authResponse = """
        {"token":"\(jwt)","pushEnabled":true}
        """.data(using: .utf8)!

        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        let credential = try await fetcher.fetchCredential(for: ["user1"])

        XCTAssertEqual(credential.expiresAt.timeIntervalSince1970, expTime, accuracy: 1)
    }

    // MARK: - Capabilities

    func testUsesEvaluatorWithConfigsCapabilityWhenDynamicConfigEnabled() async throws {
        let jwt = makeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let authResponse = "{\"token\":\"\(jwt)\",\"pushEnabled\":true}".data(using: .utf8)!
        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        let configsFetcher = DefaultCredentialFetcher(retryableHttpClient: httpClientMock, observer: ObserverSpy(), authEndpoint: authEndpoint, sdkKey: sdkKey, configsEnabled: true)

        try await configsFetcher.fetchCredential(for: "user1")

        let url = httpClientMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertTrue(url.contains("capabilities=evaluatorWithConfigs"), "URL should contain capabilities=evaluatorWithConfigs: \(url)")
    }

    func testUsesEvaluatorCapabilityByDefault() async throws {
        let jwt = makeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let authResponse = "{\"token\":\"\(jwt)\",\"pushEnabled\":true}".data(using: .utf8)!
        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        try await fetcher.fetchCredential(for: "user1")

        let url = httpClientMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertTrue(url.contains("capabilities=evaluator"), "URL should contain capabilities=evaluator: \(url)")
        XCTAssertFalse(url.contains("capabilities=evaluatorWithConfigs"), "URL should not contain capabilities=evaluatorWithConfigs: \(url)")
    }

    // MARK: - Evaluation filters

    func testIncludesFlagSetsParamWhenProvided() async throws {
        let jwt = makeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let authResponse = "{\"token\":\"\(jwt)\",\"pushEnabled\":true}".data(using: .utf8)!
        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        let filters = EvaluationFilters(flagSets: ["set_z", "set_a"])
        let filteredFetcher = DefaultCredentialFetcher(retryableHttpClient: httpClientMock, observer: ObserverSpy(), authEndpoint: authEndpoint, sdkKey: sdkKey, evaluationFilters: filters)

        try await filteredFetcher.fetchCredential(for: "user1")

        let url = httpClientMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertTrue(url.contains("sets=set_a,set_z"), "URL should contain alphabetically-sorted sets param: \(url)")
        XCTAssertFalse(url.contains("names="), "URL should not contain names param when flagNames is nil: \(url)")
    }

    func testExcludesFilterParamsWhenFiltersAreNil() async throws {
        let jwt = makeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let authResponse = "{\"token\":\"\(jwt)\",\"pushEnabled\":true}".data(using: .utf8)!
        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        try await fetcher.fetchCredential(for: "user1")

        let url = httpClientMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertFalse(url.contains("names="), "URL should not contain names param: \(url)")
        XCTAssertFalse(url.contains("sets="), "URL should not contain sets param: \(url)")
    }

    func testExcludesFilterParamsWhenListsAreEmpty() async throws {
        let jwt = makeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let authResponse = "{\"token\":\"\(jwt)\",\"pushEnabled\":true}".data(using: .utf8)!
        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        let filters = EvaluationFilters(flagNames: [], flagSets: [])
        let filteredFetcher = DefaultCredentialFetcher(retryableHttpClient: httpClientMock, observer: ObserverSpy(), authEndpoint: authEndpoint, sdkKey: sdkKey, evaluationFilters: filters)

        try await filteredFetcher.fetchCredential(for: "user1")

        let url = httpClientMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertFalse(url.contains("names="), "URL should not contain names param when flagNames is empty: \(url)")
        XCTAssertFalse(url.contains("sets="), "URL should not contain sets param when flagSets is empty: \(url)")
    }

    // MARK: - Helpers
    private func makeJwt(exp: TimeInterval) -> String {
        let header = Data("{\"alg\":\"HS256\",\"typ\":\"JWT\"}".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let payload = Data("{\"exp\":\(Int(exp)),\"iat\":\(Int(exp) - 3600)}".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let signature = "fake-signature"
        return "\(header).\(payload).\(signature)"
    }
}
