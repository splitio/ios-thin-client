import Foundation

protocol AuthProvider: Sendable {
    func register(target: String)
    func getCredential(for target: String) async throws -> JwtCredential
    func invalidate(for target: String)
}

final class DefaultAuthProvider: AuthProvider, @unchecked Sendable {

    private let credentialStorage: CredentialStorage
    private let credentialFetcher: CredentialFetcher

    private var registeredTargets = Set<String>()
    private var pendingFetches = [String: [CheckedContinuation<JwtCredential, Error>]]()
    private let lock = NSLock()

    init(credentialStorage: CredentialStorage, credentialFetcher: CredentialFetcher) {
        self.credentialStorage = credentialStorage
        self.credentialFetcher = credentialFetcher
    }

    func register(target: String) {
        let oldKey: String? = withLock(lock) {
            let oldKey = registeredTargets.isEmpty ? nil : compositeKeyUnsafe()
            let isNew = registeredTargets.insert(target).inserted
            guard isNew, registeredTargets.count > 1 else { return nil }
            return oldKey
        }

        if let oldKey {
            credentialStorage.invalidate(for: oldKey)
        }
    }

    func getCredential(for target: String) async throws -> JwtCredential {
        let key = compositeKey()

        if let cached = credentialStorage.get(for: key) {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()

            if let cached = credentialStorage.get(for: key) {
                lock.unlock()
                continuation.resume(returning: cached)
                return
            }

            let isFirstRequest = pendingFetches[key] == nil || pendingFetches[key]!.isEmpty
            if pendingFetches[key] == nil {
                pendingFetches[key] = []
            }
            pendingFetches[key]!.append(continuation)
            lock.unlock()

            if isFirstRequest {
                Task { [weak self] in
                    await self?.performFetch(for: key)
                }
            }
        }
    }

    func invalidate(for target: String) {
        credentialStorage.invalidate(for: compositeKey())
    }

    // MARK: - Private

    private func compositeKey() -> String {
        withLock(lock) { compositeKeyUnsafe() }
    }

    private func compositeKeyUnsafe() -> String {
        registeredTargets.sorted().joined(separator: ",")
    }

    private func performFetch(for key: String) async {
        let users = key.split(separator: ",").map(String.init)
        do {
            let credential = try await credentialFetcher.fetchCredential(for: users)
            credentialStorage.save(credential, for: key)
            resumePending(for: key, with: .success(credential))
        } catch {
            resumePending(for: key, with: .failure(error))
        }
    }

    private func resumePending(for key: String, with result: Result<JwtCredential, Error>) {
        let continuations = withLock(lock) {
            pendingFetches.removeValue(forKey: key) ?? []
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
