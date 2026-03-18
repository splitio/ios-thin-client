import Foundation

protocol AuthProvider: Sendable {
    func getCredential(for target: String) async throws -> JwtCredential
    func invalidate(for target: String)
}

final class DefaultAuthProvider: AuthProvider, @unchecked Sendable {

    private let credentialStorage: CredentialStorage
    private let credentialFetcher: CredentialFetcher

    private var pendingFetches = [String: [CheckedContinuation<JwtCredential, Error>]]()
    private let lock = NSLock()

    init(credentialStorage: CredentialStorage, credentialFetcher: CredentialFetcher) {
        self.credentialStorage = credentialStorage
        self.credentialFetcher = credentialFetcher
    }

    func getCredential(for target: String) async throws -> JwtCredential {
        if let cached = credentialStorage.get(for: target) {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()

            if let cached = credentialStorage.get(for: target) {
                lock.unlock()
                continuation.resume(returning: cached)
                return
            }

            let isFirstRequest = pendingFetches[target] == nil || pendingFetches[target]!.isEmpty
            if pendingFetches[target] == nil {
                pendingFetches[target] = []
            }
            pendingFetches[target]!.append(continuation)
            lock.unlock()

            if isFirstRequest {
                Task { [weak self] in
                    await self?.performFetch(for: target)
                }
            }
        }
    }

    func invalidate(for target: String) {
        credentialStorage.invalidate(for: target)
    }

    private func performFetch(for target: String) async {
        do {
            let credential = try await credentialFetcher.fetchCredential(for: [target])
            credentialStorage.save(credential, for: target)
            resumePending(for: target, with: .success(credential))
        } catch {
            resumePending(for: target, with: .failure(error))
        }
    }

    private func resumePending(for target: String, with result: Result<JwtCredential, Error>) {
        let continuations = withLock(lock) {
            pendingFetches.removeValue(forKey: target) ?? []
        }

        for continuation in continuations {
            switch result {
            case .success(let credential):
                continuation.resume(returning: credential)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}
