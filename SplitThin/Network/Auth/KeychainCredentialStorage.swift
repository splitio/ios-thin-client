import Foundation
import SplitLogging

final class KeychainCredentialStorage: CredentialStorage, @unchecked Sendable {

    // Keyed by AuthProvider's composite key. In practice only one entry is
    // present at a time (AuthProvider invalidates the old composite key on
    // target registration changes); the map shape is kept for future extensibility.
    private var cache = [String: JwtCredential]()
    private let keychainKey: String
    private let store: KeychainStore
    private let lock = NSLock()
    private var keychainAvailable = true

    init(keychainKey: String, store: KeychainStore = SystemKeychainStore()) {
        self.keychainKey = keychainKey
        self.store = store
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
        withLock(lock) { cache[key] = credential }
        persistToKeychain()
    }

    func invalidate(for key: String) {
        withLock(lock) { cache.removeValue(forKey: key) }
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

        let status = store.save(data, service: keychainKey)
        if status != errSecSuccess && status != errSecDuplicateItem {
            handleKeychainFailure("persist", status: status)
        }
    }

    private func loadFromKeychain() {
        let (status, loaded) = store.load(service: keychainKey)

        guard status == errSecSuccess, let data = loaded else {
            if status != errSecItemNotFound {
                handleKeychainFailure("load", status: status)
            }
            return
        }

        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }

        let now = Date()
        
        withLock(lock) {
            for entry in entries {
                guard let key = entry["key"] as? String,
                    let token = entry["token"] as? String,
                    let expiresAt = entry["expiresAt"] as? TimeInterval,
                    let pushEnabled = entry["pushEnabled"] as? Bool else { continue }

                let expDate = Date(timeIntervalSince1970: expiresAt)
                guard expDate > now else { continue }

                cache[key] = JwtCredential(token: token, expiresAt: expDate, pushEnabled: pushEnabled)
            }
        }
    }

    private func handleKeychainFailure(_ operation: String, status: OSStatus) {
        if keychainAvailable {
            keychainAvailable = false
            Logger.w("Keychain \(operation) failed (status: \(status)). Falling back to in-memory storage.")
        }
    }
}
