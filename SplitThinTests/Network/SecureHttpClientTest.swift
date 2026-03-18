import XCTest
@testable import SplitThin

final class SecureHttpClientTest: XCTestCase {

    func testSecureHttpClientMockReturnsGetResult() async throws {
        let mock = SecureHttpClientMock()
        let expectedResult = TestResponse(value: "test")
        mock.getResult = expectedResult

        let result: TestResponse = try await mock.get(
            url: URL(string: "https://example.com")!,
            path: "/test"
        )

        XCTAssertEqual(result.value, "test")
    }

    func testSecureHttpClientMockReturnsPostResult() async throws {
        let mock = SecureHttpClientMock()
        let expectedResult = TestResponse(value: "posted")
        mock.postResult = expectedResult

        let result: TestResponse = try await mock.post(
            url: URL(string: "https://example.com")!,
            path: "/test",
            body: nil
        )

        XCTAssertEqual(result.value, "posted")
    }

    func testSecureHttpClientMockThrowsError() async {
        let mock = SecureHttpClientMock()
        mock.errorToThrow = SecureHttpError.httpError(code: 500, message: "Server error")

        do {
            let _: TestResponse = try await mock.get(
                url: URL(string: "https://example.com")!,
                path: "/test"
            )
            XCTFail("Expected error to be thrown")
        } catch let error as SecureHttpError {
            if case .httpError(let code, _) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected httpError")
            }
        } catch {
            XCTFail("Unexpected error type")
        }
    }
}

private struct TestResponse: DynamicDecodable, Equatable {
    let value: String

    init(value: String) {
        self.value = value
    }

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any],
              let value = dict["value"] as? String else {
            throw JsonError.parsingFailed
        }
        self.value = value
    }
}
