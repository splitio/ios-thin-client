import XCTest
@testable import SplitThin

// These tests use an in-memory KeychainStore so they never touch the real macOS keychain.
// Touching the real keychain from a headless process (for example with HOME pointed at a
// directory that has no login keychain) makes macOS show a "Keychain Not Found" dialog that
// nobody can answer, which blocks the test run.
final class KeychainCredentialStorageTest: XCTestCase {

    private let testKeychainKey = "split_test_keychain_storage"

    // MARK: - In-memory behavior

    func testGetReturnsNilWhenEmpty() {
        let storage = makeStorage()

        XCTAssertNil(storage.get(for: "user1"))
    }

    func testSaveAndGetReturnsCredential() {
        let storage = makeStorage()
        let credential = makeCredential(token: "my-token")

        storage.save(credential, for: "user1")

        let result = storage.get(for: "user1")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.token, "my-token")
    }

    func testGetReturnsNilForExpiredCredential() {
        let storage = makeStorage()
        let expired = makeCredential(expiresInSeconds: -1)

        storage.save(expired, for: "user1")

        XCTAssertNil(storage.get(for: "user1"))
    }

    func testInvalidateRemovesCredential() {
        let storage = makeStorage()
        storage.save(makeCredential(), for: "user1")

        storage.invalidate(for: "user1")

        XCTAssertNil(storage.get(for: "user1"))
    }

    func testSaveOverwritesExistingCredential() {
        let storage = makeStorage()
        storage.save(makeCredential(token: "old"), for: "user1")
        storage.save(makeCredential(token: "new"), for: "user1")

        XCTAssertEqual(storage.get(for: "user1")?.token, "new")
    }

    func testDifferentKeysAreIndependent() {
        let storage = makeStorage()
        storage.save(makeCredential(token: "token-a"), for: "key-a")
        storage.save(makeCredential(token: "token-b"), for: "key-b")

        XCTAssertEqual(storage.get(for: "key-a")?.token, "token-a")
        XCTAssertEqual(storage.get(for: "key-b")?.token, "token-b")
    }

    func testInvalidateDoesNotAffectOtherKeys() {
        let storage = makeStorage()
        storage.save(makeCredential(token: "token-a"), for: "key-a")
        storage.save(makeCredential(token: "token-b"), for: "key-b")

        storage.invalidate(for: "key-a")

        XCTAssertNil(storage.get(for: "key-a"))
        XCTAssertEqual(storage.get(for: "key-b")?.token, "token-b")
    }

    // MARK: - Persistence across instances (shared in-memory store)

    func testSavedCredentialSurvivesNewInstance() {
        let store = InMemoryKeychainStore()
        let storage1 = makeStorage(store: store)
        storage1.save(makeCredential(token: "persisted-token"), for: "composite-key")

        let storage2 = makeStorage(store: store)

        let result = storage2.get(for: "composite-key")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.token, "persisted-token")
    }

    func testExpiredCredentialNotLoadedFromKeychain() {
        let store = InMemoryKeychainStore()
        let storage1 = makeStorage(store: store)
        storage1.save(makeCredential(expiresInSeconds: -1), for: "expired-key")

        let storage2 = makeStorage(store: store)

        XCTAssertNil(storage2.get(for: "expired-key"))
    }

    func testInvalidatedCredentialNotPersistedInKeychain() {
        let store = InMemoryKeychainStore()
        let storage1 = makeStorage(store: store)
        storage1.save(makeCredential(token: "to-remove"), for: "key")
        storage1.invalidate(for: "key")

        let storage2 = makeStorage(store: store)

        XCTAssertNil(storage2.get(for: "key"))
    }

    func testDifferentKeychainKeysAreIsolated() {
        let store = InMemoryKeychainStore()
        let storageA = KeychainCredentialStorage(keychainKey: "\(testKeychainKey)_A", store: store)
        let storageB = KeychainCredentialStorage(keychainKey: "\(testKeychainKey)_B", store: store)

        storageA.save(makeCredential(token: "token-A"), for: "key")
        storageB.save(makeCredential(token: "token-B"), for: "key")

        XCTAssertEqual(storageA.get(for: "key")?.token, "token-A")
        XCTAssertEqual(storageB.get(for: "key")?.token, "token-B")
    }

    func testPushEnabledIsPreservedAcrossInstances() {
        let store = InMemoryKeychainStore()
        let storage1 = makeStorage(store: store)
        storage1.save(makeCredential(pushEnabled: true), for: "key")

        let storage2 = makeStorage(store: store)

        XCTAssertEqual(storage2.get(for: "key")?.pushEnabled, true)
    }

    // MARK: - Helpers

    private func makeStorage(store: KeychainStore = InMemoryKeychainStore()) -> KeychainCredentialStorage {
        KeychainCredentialStorage(keychainKey: testKeychainKey, store: store)
    }

    private func makeCredential(token: String = "test-token", expiresInSeconds: TimeInterval = 3600, pushEnabled: Bool = false) -> JwtCredential {
        JwtCredential(token: token, expiresAt: Date().addingTimeInterval(expiresInSeconds), pushEnabled: pushEnabled)
    }
}

// Exercises the real macOS keychain. Opt-in only: set SPLIT_REAL_KEYCHAIN_TESTS=1 on a machine
// with an unlocked login keychain. Skipped otherwise so CI never shows the keychain dialog.
final class SystemKeychainStoreTest: XCTestCase {

    private let testKeychainKey = "split_test_system_keychain_store"

    private var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SPLIT_REAL_KEYCHAIN_TESTS"] == "1"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(isEnabled, "Real keychain tests are opt-in (SPLIT_REAL_KEYCHAIN_TESTS=1)")
        SystemKeychainStore().delete(service: testKeychainKey)
    }

    override func tearDown() {
        if isEnabled {
            SystemKeychainStore().delete(service: testKeychainKey)
        }
        super.tearDown()
    }

    func testSavedCredentialSurvivesNewInstanceOnSystemKeychain() {
        let storage1 = KeychainCredentialStorage(keychainKey: testKeychainKey)
        storage1.save(JwtCredential(token: "system-token", expiresAt: Date().addingTimeInterval(3600), pushEnabled: false), for: "composite-key")

        let storage2 = KeychainCredentialStorage(keychainKey: testKeychainKey)

        XCTAssertEqual(storage2.get(for: "composite-key")?.token, "system-token")
    }
}
