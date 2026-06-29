import XCTest
@testable import SplitThin

final class DefaultCredentialStorageTest: XCTestCase {

    private var storage: DefaultCredentialStorage!

    override func setUp() {
        super.setUp()
        storage = DefaultCredentialStorage()
    }

    func testGetReturnsNilWhenEmpty() {
        XCTAssertNil(storage.get(for: "user1"))
    }

    func testSaveAndGetReturnsCredential() {
        let credential = makeCredential(expiresInSeconds: 3600)

        storage.save(credential, for: "user1")

        let result = storage.get(for: "user1")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.token, credential.token)
    }

    func testGetReturnsDifferentCredentialsForDifferentTargets() {
        let cred1 = makeCredential(token: "token-1", expiresInSeconds: 3600)
        let cred2 = makeCredential(token: "token-2", expiresInSeconds: 3600)

        storage.save(cred1, for: "user1")
        storage.save(cred2, for: "user2")

        XCTAssertEqual(storage.get(for: "user1")?.token, "token-1")
        XCTAssertEqual(storage.get(for: "user2")?.token, "token-2")
    }

    func testGetReturnsNilForExpiredCredential() {
        let expired = makeCredential(expiresInSeconds: -1)

        storage.save(expired, for: "user1")

        XCTAssertNil(storage.get(for: "user1"))
    }

    func testInvalidateRemovesCredential() {
        let credential = makeCredential(expiresInSeconds: 3600)
        storage.save(credential, for: "user1")

        storage.invalidate(for: "user1")

        XCTAssertNil(storage.get(for: "user1"))
    }

    func testInvalidateDoesNotAffectOtherTargets() {
        let cred1 = makeCredential(token: "token-1", expiresInSeconds: 3600)
        let cred2 = makeCredential(token: "token-2", expiresInSeconds: 3600)
        storage.save(cred1, for: "user1")
        storage.save(cred2, for: "user2")

        storage.invalidate(for: "user1")

        XCTAssertNil(storage.get(for: "user1"))
        XCTAssertEqual(storage.get(for: "user2")?.token, "token-2")
    }

    func testSaveOverwritesExistingCredential() {
        let old = makeCredential(token: "old-token", expiresInSeconds: 3600)
        let new = makeCredential(token: "new-token", expiresInSeconds: 3600)

        storage.save(old, for: "user1")
        storage.save(new, for: "user1")

        XCTAssertEqual(storage.get(for: "user1")?.token, "new-token")
    }

    func testInvalidateForNonExistentTargetDoesNotCrash() {
        storage.invalidate(for: "nonexistent")
    }

    // MARK: - Helpers
    private func makeCredential(token: String = "test-token", expiresInSeconds: TimeInterval) -> JwtCredential {
        JwtCredential(token: token, expiresAt: Date().addingTimeInterval(expiresInSeconds), pushEnabled: true)
    }
}
