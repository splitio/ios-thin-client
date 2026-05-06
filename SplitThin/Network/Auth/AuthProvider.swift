import Foundation

protocol AuthProvider: Sendable {
    func register(target: String)
    func unregister(target: String)
    func getCredential() async throws -> JwtCredential
    func invalidate(for target: String)
}

final class DefaultAuthProvider: AuthProvider, @unchecked Sendable {

    private let credentialStorage: CredentialStorage
    private let credentialFetcher: CredentialFetcher
    private let observer: Observer

    private var registeredTargets = Set<String>()
    private var inFlightTasks = [String: Task<JwtCredential, Error>]()
    private let lock = NSLock()

    init(credentialStorage: CredentialStorage, credentialFetcher: CredentialFetcher, observer: Observer) {
        self.credentialStorage = credentialStorage
        self.credentialFetcher = credentialFetcher
        self.observer = observer
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

    func unregister(target: String) {
        let oldKey: String? = withLock(lock) {
            guard registeredTargets.contains(target) else { return nil }

            let oldKey = compositeKeyUnsafe()
            registeredTargets.remove(target)
            return oldKey
        }

        if let oldKey {
            credentialStorage.invalidate(for: oldKey)

            withLock(lock) {
                inFlightTasks.values.forEach { $0.cancel() }
                inFlightTasks.removeAll()
            }
        }
    }

    func getCredential() async throws -> JwtCredential {
        let key = compositeKey()

        // 1. Dedup.
        let valueOrTask: CachedOrTask = withLock(lock) {

            // Return value if cached..
            if let cached = credentialStorage.get(for: key) {
                return .cached(cached)
            }

            // .. return Task if not cached but request already in-flight..
            if let existing = inFlightTasks[key] {
                return .task(existing)
            }

            // .. or start the Task and return it.
            let newTask = Task { [credentialFetcher] () throws -> JwtCredential in
                let users = key.split(separator: ",").map(String.init)
                return try await credentialFetcher.fetchCredential(for: users)
            }

            inFlightTasks[key] = newTask
            return .task(newTask)
        }

        // 2. Now process the result.
        switch valueOrTask {
            case .cached(let cached):
                return cached
            case .task(let task):
                do {
                    let credential = try await task.value

                    if compositeKey() == key {
                        credentialStorage.save(credential, for: key)
                    }

                    withLock(lock) { inFlightTasks[key] = nil }

                    return credential
                } catch is CancellationError {
                    withLock(lock) { inFlightTasks[key] = nil }
                    throw CancellationError()
                } catch {
                    withLock(lock) { inFlightTasks[key] = nil }
                    throw error
                }
        }
    }

    func invalidate(for target: String) {
        let key = compositeKey()
        credentialStorage.invalidate(for: key)

        withLock(lock) {
            inFlightTasks.values.forEach { $0.cancel() }
            inFlightTasks.removeAll()
        }
    }

    // MARK: - Private

    private enum CachedOrTask {
        case cached(JwtCredential)
        case task(Task<JwtCredential, Error>)
    }

    private func compositeKey() -> String {
        withLock(lock) { compositeKeyUnsafe() }
    }

    private func compositeKeyUnsafe() -> String {
        registeredTargets.sorted().joined(separator: ",")
    }
}
