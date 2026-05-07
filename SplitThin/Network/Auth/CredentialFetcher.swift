//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Http

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
    private let observer: Observer // For logging & telemetry
    private let authEndpoint: URL
    private let sdkKey: String
    private let configsEnabled: Bool

    init(retryableHttpClient: RetryableHttpClient, observer: Observer, authEndpoint: URL, sdkKey: String, configsEnabled: Bool = false) {
        self.retryableHttpClient = retryableHttpClient
        self.observer = observer
        self.authEndpoint = authEndpoint
        self.sdkKey = sdkKey
        self.configsEnabled = configsEnabled
    }

    func fetchCredential(for users: [String]) async throws -> JwtCredential {
        observer.notify(event: .jwtFetchStarted)

        let usersParam = users.joined(separator: ",")
        var queryString = "&users=\(usersParam)"
        if configsEnabled {
            queryString += "&configs=true"
        }

        let endpoint = Endpoint.builder(baseUrl: authEndpoint, path: "auth/thin-client", defaultQueryString: queryString)
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

        observer.notify(event: .jwtFetchSucceeded(expiresAt: Int64(expiresAt.timeIntervalSince1970), pushEnabled: authResponse.pushEnabled))
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
