import XCTest
import Http
@testable import SplitThin

final class CredentialFetcherEventsTest: XCTestCase {

    private var httpClientMock: RetryableHttpClientMock!
    private var fetcher: DefaultCredentialFetcher!
    private var observerSpy: ObserverSpy!

    override func setUp() {
        super.setUp()
        httpClientMock = RetryableHttpClientMock()
        observerSpy = ObserverSpy()
        fetcher = DefaultCredentialFetcher(retryableHttpClient: httpClientMock, observer: observerSpy, authEndpoint: URL(string: "https://auth.split.io")!, sdkKey: "test-sdk-key")
    }

    override func tearDown() {
        fetcher = nil
        httpClientMock = nil
        observerSpy = nil
        super.tearDown()
    }

    func testSuccessfulFetchEmitsStartAndSucceeded() async throws {
        let jwt = makeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        httpClientMock.responses = [HttpResponse(code: 200, data: """
                                                                {"token":"\(jwt)","pushEnabled":true}
                                                                """.data(using: .utf8)!)]

        _ = try await fetcher.fetchCredential(for: ["user1"])

        XCTAssertEqual(observerSpy.eventNames, ["jwtFetchStarted", "jwtFetchSucceeded"])
    }

    func testFailedFetchEmitsOnlyStart() async {
        httpClientMock.responses = [HttpResponse(code: 200, data: nil)]

        _ = try? await fetcher.fetchCredential(for: ["user1"])

        XCTAssertEqual(observerSpy.eventNames, ["jwtFetchStarted"])
    }

    // MARK: - Helpers

    private func makeJwt(exp: TimeInterval) -> String {
        let header = Data("{\"alg\":\"HS256\",\"typ\":\"JWT\"}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let payload = Data("{\"exp\":\(Int(exp)),\"iat\":\(Int(exp) - 3600)}".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "\(header).\(payload).fake-signature"
    }
}
