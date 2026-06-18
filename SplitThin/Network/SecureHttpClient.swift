//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import CryptoKit
import Foundation
import Http
import Logging

enum SecureHttpError: Error {
    case invalidResponse
    case httpError(code: Int, message: String)
    case decodingError(Error)
    case networkError(Error)
}

protocol SecureHttpClient: Sendable {
    func fetchEvaluations(target: Target, filters: EvaluationFilters?) async throws -> HttpResponse
    func postEvents(payload: Data) async throws -> HttpResponse
    func postTelemetry(payload: Data) async throws -> HttpResponse
}

final class DefaultSecureHttpClient: SecureHttpClient, @unchecked Sendable {

    private let retryableHttpClient: RetryableHttpClient
    private let authProvider: AuthProvider
    private let serviceEndpoints: ServiceEndpoints
    private let configsEnabled: Bool
    private let apiKey: String
    private let evaluationStorage: EvaluationReadStorage?

    init(retryableHttpClient: RetryableHttpClient, authProvider: AuthProvider, serviceEndpoints: ServiceEndpoints, configsEnabled: Bool = false, apiKey: String, evaluationStorage: EvaluationReadStorage? = nil) {
        self.retryableHttpClient = retryableHttpClient
        self.authProvider = authProvider
        self.serviceEndpoints = serviceEndpoints
        self.configsEnabled = configsEnabled
        self.apiKey = apiKey
        self.evaluationStorage = evaluationStorage
    }

    func fetchEvaluations(target: Target, filters: EvaluationFilters?) async throws -> HttpResponse {
        let credential = try await authProvider.getCredential()
        let since = await evaluationStorage?.lastChangeNumber(target: target) ?? -1

        let response = try await performEvaluationsRequest(target: target, filters: filters, since: since, token: credential.token)

        if response.code == 401 {
            authProvider.invalidate(for: target.matchingKey)
            let refreshedCredential = try await authProvider.getCredential()
            return try await performEvaluationsRequest(target: target, filters: filters, since: since, token: refreshedCredential.token)
        }

        return response
    }

    func postEvents(payload: Data) async throws -> HttpResponse {
        let endpoint = Endpoint.builder(baseUrl: serviceEndpoints.eventsEndpoint, path: "api/events/bulk")
                               .set(method: .post)
                               .add(header: "Content-Type", withValue: "application/json")
                               .add(header: "Authorization", withValue: "Bearer \(apiKey)")
                               .add(header: "SplitSDKVersion", withValue: "ios-\(Version.semantic)")
                               .build()

        return try await retryableHttpClient.execute(endpoint, category: .events, body: payload)
    }

    func postTelemetry(payload: Data) async throws -> HttpResponse {
        let endpoint = Endpoint.builder(baseUrl: serviceEndpoints.telemetryServiceEndpoint, path: "api/v1/metrics/usage")
                               .set(method: .post)
                               .add(header: "Content-Type", withValue: "application/json")
                               .add(header: "X-Harness-FME-SDK-Version", withValue: "ios-\(Version.semantic)")
                               .build()

        return try await retryableHttpClient.execute(endpoint, category: .telemetry, body: payload)
    }

    private func performEvaluationsRequest(target: Target, filters: EvaluationFilters?, since: Int64, token: String) async throws -> HttpResponse {
        let body = buildEvaluationsBody(target: target, filters: filters)
        let digest = body.map(Self.contentDigest(for:)) ?? ""

        let endpoint = Endpoint.builder(baseUrl: serviceEndpoints.sdkEndpoint, path: "api/evaluations", defaultQueryString: "&since=\(since)")
            .set(method: .post)
            .add(header: "Content-Type", withValue: "application/json")
            .add(header: "Authorization", withValue: "Bearer \(token)")
            .add(header: "X-Harness-FME-SDK-Version", withValue: "ios-\(Version.semantic)")
            .add(header: "X-Harness-FME-Content-Digest", withValue: digest)
            .build()

        return try await retryableHttpClient.execute(endpoint, category: .evaluations, body: body)
    }
}

// MARK: Formatting Methods
extension DefaultSecureHttpClient {

    //
    // Evaluations request body.
    //
    // Always includes `configs` and `key`. Optional fields (`attributes`, `bucketingKey`, `sets`)
    // are omitted when not set / empty. `sets` is sorted to ensure determinism.
    //
    private func buildEvaluationsBody(target: Target, filters: EvaluationFilters?) -> Data? {
        // All keys are always present (even when empty) so the content digest matches
        // the server's canonical form: missing optionals become `null` / `[]` / `{}`.
        var attributes: [String: Any] = [:]
        if let targetAttributes = target.attributes, !targetAttributes.isEmpty, JSONSerialization.isValidJSONObject(targetAttributes) {
            attributes = alphabetical(targetAttributes)
        }

        let body: [String: Any] = [
            "attributes": attributes,
            "bucketingKey": target.bucketingKey ?? NSNull(),
            "configs": configsEnabled,
            "key": target.matchingKey,
            "sets": (filters?.flagSets ?? []).sorted()
        ]

        do {
            return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        } catch {
            Logger.e("SecureHttpClient: Failed to serialize evaluations body: \(error)")
            return nil
        }
    }

    //
    // X-Harness-FME-Content-Digest header value for the given body.
    //
    // Format: SHA512(body) → first 64 bits → base64 (no padding).
    //
    static func contentDigest(for body: Data) -> String {
        let digest = SHA512.hash(data: body)
        let first64Bits = Data(digest.prefix(8))
        return first64Bits.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    private func alphabetical(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in dict {
            switch value {
                case let array as [String]: result[key] = array.sorted()
                case let array as [Int]:    result[key] = array.sorted()
                case let array as [Double]: result[key] = array.sorted()
                case let array as [Bool]:   result[key] = array.sorted { (!$0 && $1) }
                default: result[key] = value
            }
        }

        return result
    }
}
