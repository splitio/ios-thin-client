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
        XCTAssertTrue(call.endpoint.url.absoluteString.contains("auth/thin-client"))
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

    func testFetchCredentialThrowsOnNon200() async throws {
        httpClientMock.responses = [HttpResponse(code: 401, data: nil)]

        do {
            try await fetcher.fetchCredential(for: "user1")
            XCTFail("Expected error")
        } catch is CredentialFetcherError {
        } catch {
            XCTFail("Unexpected error type: \(error)")
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

    // MARK: - Configs enabled

    func testIncludesConfigsParamWhenEnabled() async throws {
        let jwt = makeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let authResponse = "{\"token\":\"\(jwt)\",\"pushEnabled\":true}".data(using: .utf8)!
        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        let configsFetcher = DefaultCredentialFetcher(retryableHttpClient: httpClientMock, observer: ObserverSpy(), authEndpoint: authEndpoint, sdkKey: sdkKey, configsEnabled: true)

        try await configsFetcher.fetchCredential(for: "user1")

        let url = httpClientMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertTrue(url.contains("configs=true"), "URL should contain configs param: \(url)")
    }

    func testExcludesConfigsParamWhenDisabled() async throws {
        let jwt = makeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let authResponse = "{\"token\":\"\(jwt)\",\"pushEnabled\":true}".data(using: .utf8)!
        httpClientMock.responses = [HttpResponse(code: 200, data: authResponse)]

        try await fetcher.fetchCredential(for: "user1")

        let url = httpClientMock.executeCalls[0].endpoint.url.absoluteString
        XCTAssertFalse(url.contains("configs"), "URL should not contain configs param: \(url)")
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
