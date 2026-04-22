import Foundation

protocol AuthProvider: Sendable {
    func getCredential(for target: String) async throws -> JwtCredential
    func invalidate(for target: String)
}

final class DefaultAuthProvider: AuthProvider, @unchecked Sendable {

    private let credentialStorage: CredentialStorage
    private let credentialFetcher: CredentialFetcher
    private let observer: Observer // For logging & telemetry

    private var pendingFetches = [String: [CheckedContinuation<JwtCredential, Error>]]()
    private let lock = NSLock()

    init(credentialStorage: CredentialStorage, credentialFetcher: CredentialFetcher, observer: Observer) {
        self.credentialStorage = credentialStorage
        self.credentialFetcher = credentialFetcher
        self.observer = observer
    }

    func getCredential(for target: String) async throws -> JwtCredential {
        if let cached = credentialStorage.get(for: target) {
            observer.notify(event: .jwtRequestStarted(cached: true))
            return cached
        }

        observer.notify(event: .jwtRequestStarted(cached: false))

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
        observer.notify(event: .jwtExpiredOrInvalid)
        credentialStorage.invalidate(for: target)
    }

    private func performFetch(for target: String) async {
        do {
            let credential = try await credentialFetcher.fetchCredential(for: [target])
            credentialStorage.save(credential, for: target)
            observer.notify(event: .jwtStored(secureStorage: false))
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
