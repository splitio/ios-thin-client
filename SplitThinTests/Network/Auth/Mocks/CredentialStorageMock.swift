import Foundation
@testable import SplitThin

final class CredentialStorageMock: CredentialStorage, @unchecked Sendable {

    var credentials = [String: JwtCredential]()
    var getCallCount = 0
    var saveCallCount = 0
    var invalidateCallCount = 0
    var lastTargetGet: String?
    var lastTargetSave: String?
    var lastTargetInvalidate: String?
    private let lock = NSLock()

    func get(for target: String) -> JwtCredential? {
        lock.lock()
        defer { lock.unlock() }

        getCallCount += 1
        lastTargetGet = target
        return credentials[target]
    }

    func save(_ credential: JwtCredential, for target: String) {
        lock.lock()
        defer { lock.unlock() }

        saveCallCount += 1
        lastTargetSave = target
        credentials[target] = credential
    }

    func invalidate(for target: String) {
        lock.lock()
        defer { lock.unlock() }

        invalidateCallCount += 1
        lastTargetInvalidate = target
        credentials.removeValue(forKey: target)
    }
}
