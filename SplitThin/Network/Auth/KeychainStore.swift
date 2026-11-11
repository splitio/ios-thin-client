import Foundation

/// Storage backend for `KeychainCredentialStorage`. The system implementation talks to the
/// real keychain; tests inject an in-memory one so they never touch the keychain.
protocol KeychainStore: Sendable {
    /// Returns the stored data for `service`, or `errSecItemNotFound` status with nil data.
    func load(service: String) -> (status: OSStatus, data: Data?)
    /// Replaces any existing item for `service` with `data`. Returns the OSStatus of the add.
    func save(_ data: Data, service: String) -> OSStatus
    func delete(service: String)
}

final class SystemKeychainStore: KeychainStore {

    private static let account = "credentials"

    func load(service: String) -> (status: OSStatus, data: Data?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    func save(_ data: Data, service: String) -> OSStatus {
        let query = baseQuery(service: service)
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    func delete(service: String) {
        SecItemDelete(baseQuery(service: service) as CFDictionary)
    }

    private func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account
        ]
    }
}
