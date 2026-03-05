import XCTest
@testable import SplitThin

final class JwtCredentialTest: XCTestCase {

    func testProperties() {
        let expiry = Date(timeIntervalSince1970: 1700000000)
        let credential = JwtCredential(token: "abc.def.ghi", expiresAt: expiry, pushEnabled: true)

        XCTAssertEqual(credential.token, "abc.def.ghi")
        XCTAssertEqual(credential.expiresAt, expiry)
        XCTAssertTrue(credential.pushEnabled)
    }

    func testPushDisabled() {
        let credential = JwtCredential(token: "token", expiresAt: Date(), pushEnabled: false)
        XCTAssertFalse(credential.pushEnabled)
    }
}
