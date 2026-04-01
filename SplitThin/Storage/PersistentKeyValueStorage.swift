import Foundation

public protocol PersistentKeyValueStorage: Sendable {
    func read(key: String) async -> Data?
    func write(key: String, value: Data) async throws
    func remove(key: String) async throws
}
