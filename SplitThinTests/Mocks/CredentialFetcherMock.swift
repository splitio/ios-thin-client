import Foundation
@testable import SplitThin

final class CredentialFetcherMock: CredentialFetcher, @unchecked Sendable {

    var credentialToReturn: JwtCredential?
    var errorToThrow: Error?
    var fetchCallCount = 0
    var lastUsersRequested: [String]?
    var delay: TimeInterval = 0
    private let lock = NSLock()

    func fetchCredential(for users: [String]) async throws -> JwtCredential {
        withLock(lock) {
            fetchCallCount += 1
            lastUsersRequested = users
        }

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if let error = errorToThrow {
            throw error
        }

        guard let credential = credentialToReturn else {
            fatalError("CredentialFetcherMock: credentialToReturn not set")
        }

        return credential
    }
}
