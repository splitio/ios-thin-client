import XCTest
@testable import SplitThin

final class AuthProviderTest: XCTestCase {

    func testAuthProviderMockReturnsCredential() async throws {
        let mock = AuthProviderMock()
        let expectedCredential = JwtCredential(
            token: "test-token",
            expiresAt: Date().addingTimeInterval(3600),
            pushEnabled: true
        )
        mock.credentialToReturn = expectedCredential

        let credential = try await mock.getCredential()

        XCTAssertEqual(credential.token, "test-token")
        XCTAssertTrue(credential.pushEnabled)
        XCTAssertEqual(mock.getCredentialCallCount, 1)
    }

    func testAuthProviderMockThrowsError() async {
        let mock = AuthProviderMock()
        mock.errorToThrow = SecureHttpError.invalidResponse

        do {
            _ = try await mock.getCredential()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(mock.getCredentialCallCount, 1)
        }
    }
}
