import XCTest
import Security
@testable import SplitThin

final class KeychainCredentialStorageTest: XCTestCase {

    private let testKeychainKey = "split_test_keychain_storage"

    override func setUp() {
        super.setUp()
        cleanKeychain()
    }

    override func tearDown() {
        cleanKeychain()
        super.tearDown()
    }

    // MARK: - In-memory behavior

    func testGetReturnsNilWhenEmpty() {
        let storage = KeychainCredentialStorage(keychainKey: testKeychainKey)

        XCTAssertNil(storage.get(for: "user1"))
    }

    func testSaveAndGetReturnsCredential() {
        let storage = KeychainCredentialStorage(keychainKey: testKeychainKey)
        let credential = makeCredential(token: "my-token")

        storage.save(credential, for: "user1")

        let result = storage.get(for: "user1")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.token, "my-token")
    }

    func testGetReturnsNilForExpiredCredential() {
        let storage = KeychainCredentialStorage(keychainKey: testKeychainKey)
        let expired = makeCredential(expiresInSeconds: -1)

        storage.save(expired, for: "user1")

        XCTAssertNil(storage.get(for: "user1"))
    }

    func testInvalidateRemovesCredential() {
        let storage = KeychainCredentialStorage(keychainKey: testKeychainKey)
        storage.save(makeCredential(), for: "user1")

        storage.invalidate(for: "user1")

        XCTAssertNil(storage.get(for: "user1"))
    }

    func testSaveOverwritesExistingCredential() {
        let storage = KeychainCredentialStorage(keychainKey: testKeychainKey)
        storage.save(makeCredential(token: "old"), for: "user1")
        storage.save(makeCredential(token: "new"), for: "user1")

        XCTAssertEqual(storage.get(for: "user1")?.token, "new")
    }

    func testDifferentKeysAreIndependent() {
        let storage = KeychainCredentialStorage(keychainKey: testKeychainKey)
        storage.save(makeCredential(token: "token-a"), for: "key-a")
        storage.save(makeCredential(token: "token-b"), for: "key-b")

        XCTAssertEqual(storage.get(for: "key-a")?.token, "token-a")
        XCTAssertEqual(storage.get(for: "key-b")?.token, "token-b")
    }

    func testInvalidateDoesNotAffectOtherKeys() {
        let storage = KeychainCredentialStorage(keychainKey: testKeychainKey)
        storage.save(makeCredential(token: "token-a"), for: "key-a")
        storage.save(makeCredential(token: "token-b"), for: "key-b")

        storage.invalidate(for: "key-a")

        XCTAssertNil(storage.get(for: "key-a"))
        XCTAssertEqual(storage.get(for: "key-b")?.token, "token-b")
    }

    // MARK: - Keychain persistence

    func testSavedCredentialSurvivesNewInstance() throws {
        try skipIfKeychainUnavailable()
        let storage1 = KeychainCredentialStorage(keychainKey: testKeychainKey)
        storage1.save(makeCredential(token: "persisted-token"), for: "composite-key")

        let storage2 = KeychainCredentialStorage(keychainKey: testKeychainKey)

        let result = storage2.get(for: "composite-key")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.token, "persisted-token")
    }

    func testExpiredCredentialNotLoadedFromKeychain() throws {
        try skipIfKeychainUnavailable()
        let storage1 = KeychainCredentialStorage(keychainKey: testKeychainKey)
        storage1.save(makeCredential(expiresInSeconds: -1), for: "expired-key")

        let storage2 = KeychainCredentialStorage(keychainKey: testKeychainKey)

        XCTAssertNil(storage2.get(for: "expired-key"))
    }

    func testInvalidatedCredentialNotPersistedInKeychain() throws {
        try skipIfKeychainUnavailable()
        let storage1 = KeychainCredentialStorage(keychainKey: testKeychainKey)
        storage1.save(makeCredential(token: "to-remove"), for: "key")
        storage1.invalidate(for: "key")

        let storage2 = KeychainCredentialStorage(keychainKey: testKeychainKey)

        XCTAssertNil(storage2.get(for: "key"))
    }

    func testDifferentKeychainKeysAreIsolated() throws {
        try skipIfKeychainUnavailable()
        let storageA = KeychainCredentialStorage(keychainKey: "\(testKeychainKey)_A")
        let storageB = KeychainCredentialStorage(keychainKey: "\(testKeychainKey)_B")

        storageA.save(makeCredential(token: "token-A"), for: "key")
        storageB.save(makeCredential(token: "token-B"), for: "key")

        XCTAssertEqual(storageA.get(for: "key")?.token, "token-A")
        XCTAssertEqual(storageB.get(for: "key")?.token, "token-B")

        cleanKeychain(key: "\(testKeychainKey)_A")
        cleanKeychain(key: "\(testKeychainKey)_B")
    }

    func testPushEnabledIsPreservedAcrossInstances() throws {
        try skipIfKeychainUnavailable()
        let storage1 = KeychainCredentialStorage(keychainKey: testKeychainKey)
        storage1.save(makeCredential(pushEnabled: true), for: "key")

        let storage2 = KeychainCredentialStorage(keychainKey: testKeychainKey)

        XCTAssertEqual(storage2.get(for: "key")?.pushEnabled, true)
    }

    // MARK: - Helpers

    private func makeCredential(token: String = "test-token", expiresInSeconds: TimeInterval = 3600, pushEnabled: Bool = false) -> JwtCredential {
        JwtCredential(token: token, expiresAt: Date().addingTimeInterval(expiresInSeconds), pushEnabled: pushEnabled)
    }

    private func cleanKeychain(key: String? = nil) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key ?? testKeychainKey,
            kSecAttrAccount as String: "credentials"
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Since we don't have entitlements options on SPM, some tests fail because
    // iOS does not give access to Keychain. 
    // However, this tests run well on macOS where permissions aren't so strict.
    // They are skipped on iOS (because they fail), and must be tested manually.
    // They have been tested manually and the behavior is the expected.
    //
    // For a Tapp, entitlements must be granted at the project level to accces Keychain.
    //
    private func skipIfKeychainUnavailable() throws {
        let testKey = "keychain_availability_test"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: testKey,
            kSecAttrAccount as String: "test",
            kSecValueData as String: Data("test".utf8)
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        SecItemDelete(query as CFDictionary)

        if status == errSecMissingEntitlement {
            throw XCTSkip("Keychain not available (missing entitlements)")
        }
    }
}
