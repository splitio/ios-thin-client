import Foundation
import Http
import Logging

enum CredentialFetcherError: Error {
    case invalidAuthResponse
    case missingTokenExpiration
    case networkError(Error)
}

protocol CredentialFetcher: Sendable {
    func fetchCredential(for users: [String]) async throws -> JwtCredential
}

final class DefaultCredentialFetcher: CredentialFetcher, @unchecked Sendable {

    private let retryableHttpClient: RetryableHttpClient
    private let authEndpoint: URL
    private let sdkKey: String

    init(retryableHttpClient: RetryableHttpClient, authEndpoint: URL, sdkKey: String) {
        self.retryableHttpClient = retryableHttpClient
        self.authEndpoint = authEndpoint
        self.sdkKey = sdkKey
    }

    func fetchCredential(for users: [String]) async throws -> JwtCredential {
        let usersParam = users.joined(separator: ",")
        let endpoint = Endpoint.builder(baseUrl: authEndpoint, path: "auth/thin-client", defaultQueryString: "&users=\(usersParam)")
                               .set(method: .get)
                               .add(header: "Authorization", withValue: "Bearer \(sdkKey)")
                               .add(header: "Content-Type", withValue: "application/json")
                               .build()

        let response = try await retryableHttpClient.execute(endpoint, category: .auth)

        guard response.isSuccess, let data = response.data else {
            throw CredentialFetcherError.invalidAuthResponse
        }

        let authResponse = try Json.decode(from: data, to: AuthResponse.self)
        let expiresAt = try extractExpiration(from: authResponse.token)

        return JwtCredential(token: authResponse.token, expiresAt: expiresAt, pushEnabled: authResponse.pushEnabled)
    }

    private func extractExpiration(from jwt: String) throws -> Date {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else {
            throw CredentialFetcherError.missingTokenExpiration
        }

        var payload = String(parts[1])
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload) else {
            throw CredentialFetcherError.missingTokenExpiration
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = jsonObject as? [String: Any], let exp = dict["exp"] as? TimeInterval else {
            throw CredentialFetcherError.missingTokenExpiration
        }
        return Date(timeIntervalSince1970: exp)
    }
}
