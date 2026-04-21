import Foundation
import Logging

final class KeychainCredentialStorage: CredentialStorage, @unchecked Sendable {

    private let keychainKey: String
    private var cache = [String: JwtCredential]()
    private let lock = NSLock()
    private var keychainAvailable = true

    init(keychainKey: String) {
        self.keychainKey = keychainKey
        loadFromKeychain()
    }

    func get(for key: String) -> JwtCredential? {
        withLock(lock) {
            guard let credential = cache[key], credential.expiresAt > Date() else {
                return nil
            }
            return credential
        }
    }

    func save(_ credential: JwtCredential, for key: String) {
        withLock(lock) {
            cache[key] = credential
        }
        persistToKeychain()
    }

    func invalidate(for key: String) {
        withLock(lock) {
            cache.removeValue(forKey: key)
        }
        persistToKeychain()
    }

    // MARK: - Keychain

    private func persistToKeychain() {
        let snapshot = withLock(lock) { cache }

        let entries = snapshot.compactMap { key, cred -> [String: Any]? in
            guard cred.expiresAt > Date() else { return nil }
            return [
                "key": key,
                "token": cred.token,
                "expiresAt": cred.expiresAt.timeIntervalSince1970,
                "pushEnabled": cred.pushEnabled
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: entries) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainKey,
            kSecAttrAccount as String: "credentials"
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess && status != errSecDuplicateItem {
            handleKeychainFailure("persist", status: status)
        }
    }

    private func loadFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainKey,
            kSecAttrAccount as String: "credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                handleKeychainFailure("load", status: status)
            }
            return
        }

        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        let now = Date()
        lock.lock()
        for entry in entries {
            guard let key = entry["key"] as? String,
                  let token = entry["token"] as? String,
                  let expiresAt = entry["expiresAt"] as? TimeInterval,
                  let pushEnabled = entry["pushEnabled"] as? Bool else { continue }

            let expDate = Date(timeIntervalSince1970: expiresAt)
            guard expDate > now else { continue }

            cache[key] = JwtCredential(token: token, expiresAt: expDate, pushEnabled: pushEnabled)
        }
        lock.unlock()
    }

    private func handleKeychainFailure(_ operation: String, status: OSStatus) {
        if keychainAvailable {
            keychainAvailable = false
            Logger.w("Keychain \(operation) failed (status: \(status)). Falling back to in-memory storage.")
        }
    }
}
