//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

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

    init(retryableHttpClient: RetryableHttpClient, authProvider: AuthProvider, serviceEndpoints: ServiceEndpoints, configsEnabled: Bool = false, apiKey: String) {
        self.retryableHttpClient = retryableHttpClient
        self.authProvider = authProvider
        self.serviceEndpoints = serviceEndpoints
        self.configsEnabled = configsEnabled
        self.apiKey = apiKey
    }

    func fetchEvaluations(target: Target, filters: EvaluationFilters?) async throws -> HttpResponse {
        let credential = try await authProvider.getCredential()

        let response = try await performEvaluationsRequest(target: target, filters: filters, token: credential.token)

        if response.code == 401 {
            authProvider.invalidate(for: target.matchingKey)
            let refreshedCredential = try await authProvider.getCredential()
            return try await performEvaluationsRequest(target: target, filters: filters, token: refreshedCredential.token)
        }

        return response
    }

    func postEvents(payload: Data) async throws -> HttpResponse {
        let endpoint = Endpoint.builder(baseUrl: serviceEndpoints.eventsEndpoint, path: "api/events/bulk")
                               .set(method: .post)
                               .add(header: "Content-Type", withValue: "application/json")
                               .add(header: "Authorization", withValue: "Bearer \(apiKey)")
                               .build()

        return try await retryableHttpClient.execute(endpoint, category: .events, body: payload)
    }

    func postTelemetry(payload: Data) async throws -> HttpResponse {
        let endpoint = Endpoint.builder(baseUrl: serviceEndpoints.telemetryServiceEndpoint, path: "api/v1/metrics/usage")
                               .set(method: .post)
                               .add(header: "Content-Type", withValue: "application/json")
                               .build()

        return try await retryableHttpClient.execute(endpoint, category: .telemetry, body: payload)
    }

    private func performEvaluationsRequest(target: Target, filters: EvaluationFilters?, token: String) async throws -> HttpResponse {
        let queryString = buildEvaluationsQueryString(target: target, filters: filters)
        let digest = ContentDigest.compute(for: target)

        let endpoint = Endpoint.builder(baseUrl: serviceEndpoints.sdkEndpoint, path: "api/evaluations", defaultQueryString: queryString)
            .set(method: .post)
            .add(header: "Content-Type", withValue: "application/json")
            .add(header: "Authorization", withValue: "Bearer \(token)")
            .add(header: "X-Harness-FME-Content-Digest", withValue: digest)
            .build()
        
        let body = serializeAttributes(target.attributes)
        return try await retryableHttpClient.execute(endpoint, category: .evaluations, body: body)
    }
}

// MARK: Formatting Methods
extension DefaultSecureHttpClient {

    //
    // Evaluations URL query (ensures it will always arrive in alphabetical order, even if new params are added).
    //
    // In case of adding *lists* as values, make sure they are ordered as well using .sorted()
    //
    private func buildEvaluationsQueryString(target: Target, filters: EvaluationFilters?) -> String {
        var params: [(String, String)] = []

        if let flagNames = filters?.flagNames, !flagNames.isEmpty {
            params.append(("&names", flagNames.sorted().joined(separator: ","))) // Automatic sorting
        }
        if let flagSets = filters?.flagSets, !flagSets.isEmpty {
            params.append(("&sets", flagSets.sorted().joined(separator: ","))) // Automatic sorting
        }
        params.append(("&since", "-1"))
        params.append(("&user", target.matchingKey))
        params.append(("&capabilities", configsEnabled ? "evaluatorWithConfigs" : "evaluator"))

        return params.sorted { $0.0 < $1.0 }.map { "\($0)=\($1)" }.joined() // Automatic sorting
    }

    //
    // Attributes serialization
    //
    private func serializeAttributes(_ attributes: [String: Any]?) -> Data? {
        guard let attributes, !attributes.isEmpty else {
            return "{}".data(using: .utf8)
        }

        do {
            return try JSONSerialization.data(withJSONObject: ["attributes": attributes])
        } catch {
            Logger.e("SecureHttpClient: Failed to serialize attributes: \(error)")
            return "{}".data(using: .utf8)
        }
    }
}
