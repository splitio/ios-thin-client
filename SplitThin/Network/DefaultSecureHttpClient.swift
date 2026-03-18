import Foundation
import Http

final class DefaultSecureHttpClient: SecureHttpClient, @unchecked Sendable {

    private let httpClient: HttpClient
    private let authProvider: AuthProvider
    private var cachedCredential: JwtCredential?
    private let lock = NSLock()

    init(httpClient: HttpClient, authProvider: AuthProvider) {
        self.httpClient = httpClient
        self.authProvider = authProvider
    }

    func get<T: DynamicDecodable>(url: URL, path: String?) async throws -> T {
        let data = try await request(url: url, path: path, method: .get, body: nil)
        return try Json.decode(from: data, to: T.self)
    }

    func getArray<T: DynamicDecodable>(url: URL, path: String?) async throws -> [T] {
        let data = try await request(url: url, path: path, method: .get, body: nil)
        return try Json.decodeArray(from: data, to: T.self)
    }

    func post<T: DynamicDecodable>(url: URL, path: String?, body: Data?) async throws -> T {
        let data = try await request(url: url, path: path, method: .post, body: body)
        return try Json.decode(from: data, to: T.self)
    }

    private func request(url: URL, path: String?, method: HttpMethod, body: Data?) async throws -> Data {
        let credential = try await getValidCredential()

        let endpoint = Endpoint.builder(baseUrl: url, path: path)
                               .set(method: method)
                               .add(header: "Authorization", withValue: "Bearer \(credential.token)")
                               .add(header: "Content-Type", withValue: "application/json")
                               .build()

        let response = try await performRequest(endpoint: endpoint, body: body)

        guard response.isSuccess, let data = response.data else {
            throw SecureHttpError.httpError(code: response.code, message: "HTTP error")
        }

        return data
    }

    private func performRequest(endpoint: Endpoint, body: Data?) async throws -> HttpResponse {
        try await withCheckedThrowingContinuation { continuation in
            do {
                _ = try httpClient.sendRequest(endpoint: endpoint, parameters: nil, headers: nil, body: body)
                                  .getResponse { response in
                    continuation.resume(returning: response)
                } errorHandler: { error in
                    continuation.resume(throwing: SecureHttpError.networkError(error))
                }
            } catch {
                continuation.resume(throwing: SecureHttpError.networkError(error))
            }
        }
    }

    private func getValidCredential() async throws -> JwtCredential {
        if let cached = getCachedCredential() {
            return cached
        }

        let newCredential = try await authProvider.getCredential()
        setCachedCredential(newCredential)

        return newCredential
    }

    private func getCachedCredential() -> JwtCredential? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached = cachedCredential, cached.expiresAt > Date() else {
            return nil
        }
        return cached
    }

    private func setCachedCredential(_ credential: JwtCredential) {
        lock.lock()
        defer { lock.unlock() }
        cachedCredential = credential
    }
}
