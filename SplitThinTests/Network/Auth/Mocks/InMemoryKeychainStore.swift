import Foundation
import Security
@testable import SplitThin

/// Keychain stand-in that keeps items in memory. Use it in tests instead of the system keychain.
final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {

    private var items = [String: Data]()
    private let lock = NSLock()

    func load(service: String) -> (status: OSStatus, data: Data?) {
        withLock(lock) {
            guard let data = items[service] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    func save(_ data: Data, service: String) -> OSStatus {
        withLock(lock) { items[service] = data }
        return errSecSuccess
    }

    func delete(service: String) {
        withLock(lock) { _ = items.removeValue(forKey: service) }
    }
}
