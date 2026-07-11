//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Http

enum CredentialFetcherError: Error {
    case unauthorized
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
    private let evaluationFilters: EvaluationFilters?

    init(retryableHttpClient: RetryableHttpClient, observer: Observer, authEndpoint: URL, sdkKey: String, configsEnabled: Bool = false, evaluationFilters: EvaluationFilters? = nil) {
        self.retryableHttpClient = retryableHttpClient
        self.observer = observer
        self.authEndpoint = authEndpoint
        self.sdkKey = sdkKey
        self.configsEnabled = configsEnabled
        self.evaluationFilters = evaluationFilters
    }

    func fetchCredential(for users: [String]) async throws -> JwtCredential {
        observer.notify(event: .jwtFetchStarted)

        guard let url = buildAuthUrl(for: users) else {
            throw CredentialFetcherError.invalidAuthResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(sdkKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios-\(Version.semantic)", forHTTPHeaderField: "X-Harness-FME-SDK-Version")

        let response = try await retryableHttpClient.execute(request: request, category: .auth)

        if response.code == 401 {
            throw CredentialFetcherError.unauthorized
        }

        guard response.isSuccess, let data = response.data else {
            throw CredentialFetcherError.invalidAuthResponse
        }

        let authResponse = try Json.decode(from: data, to: AuthResponse.self)
        let expiresAt = try extractExpiration(from: authResponse.token)
 
        observer.notify(event: .jwtFetchSucceeded(expiresAt: Int64(expiresAt.timeIntervalSince1970), pushEnabled: authResponse.pushEnabled))
        return JwtCredential(token: authResponse.token, expiresAt: expiresAt, pushEnabled: authResponse.pushEnabled, connDelay: authResponse.connDelay)
    }

    // Builds the auth URL with a manually percent-encoded query.
    // The key values must be percent-encoded so query sub-delimiters that are part of the key
    // (comma, &, +, #, space, =, ...) don't corrupt the query structure or get split server-side
    private func buildAuthUrl(for users: [String]) -> URL? {
        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)
        let basePath = components?.path ?? ""
        components?.path = basePath.hasSuffix("/") ? "\(basePath)api/v3/auth" : "\(basePath)/api/v3/auth"

        var parts: [String] = [configsEnabled ? "capabilities=evaluatorWithConfigs" : "capabilities=evaluator"]
        parts += users.map { "key=\(Self.percentEncodedKey($0))" }
        if let flagSets = evaluationFilters?.flagSets, !flagSets.isEmpty {
            parts.append("sets=\(flagSets.sorted().joined(separator: ","))")
        }
        components?.percentEncodedQuery = parts.joined(separator: "&")

        return components?.url
    }

    private static let unreservedKeyCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func percentEncodedKey(_ key: String) -> String {
        key.addingPercentEncoding(withAllowedCharacters: unreservedKeyCharacters) ?? key
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
