//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Http

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

    init(retryableHttpClient: RetryableHttpClient, authProvider: AuthProvider, serviceEndpoints: ServiceEndpoints) {
        self.retryableHttpClient = retryableHttpClient
        self.authProvider = authProvider
        self.serviceEndpoints = serviceEndpoints
    }

    func fetchEvaluations(target: Target, filters: EvaluationFilters?) async throws -> HttpResponse {
        let credential = try await authProvider.getCredential(for: target.matchingKey)

        let response = try await performEvaluationsRequest(target: target, filters: filters, token: credential.token)

        if response.code == 401 {
            authProvider.invalidate(for: target.matchingKey)
            let refreshedCredential = try await authProvider.getCredential(for: target.matchingKey)
            return try await performEvaluationsRequest(target: target, filters: filters, token: refreshedCredential.token)
        }

        return response
    }

    func postEvents(payload: Data) async throws -> HttpResponse {
        let endpoint = Endpoint.builder(baseUrl: serviceEndpoints.eventsEndpoint, path: "events/bulk")
                               .set(method: .post)
                               .add(header: "Content-Type", withValue: "application/json")
                               .build()

        return try await retryableHttpClient.execute(endpoint, category: .events, body: payload)
    }

    func postTelemetry(payload: Data) async throws -> HttpResponse {
        let endpoint = Endpoint.builder(baseUrl: serviceEndpoints.telemetryServiceEndpoint, path: "metrics/usage")
                               .set(method: .post)
                               .add(header: "Content-Type", withValue: "application/json")
                               .build()

        return try await retryableHttpClient.execute(endpoint, category: .telemetry, body: payload)
    }

    private func performEvaluationsRequest(target: Target, filters: EvaluationFilters?, token: String) async throws -> HttpResponse {
        var queryString = "&user=\(target.matchingKey)&since=-1"
        if let flagNames = filters?.flagNames, !flagNames.isEmpty {
            queryString += "&names=\(flagNames.joined(separator: ","))"
        } else if let flagSets = filters?.flagSets, !flagSets.isEmpty {
            queryString += "&sets=\(flagSets.joined(separator: ","))"
        }
        
        let endpoint = Endpoint.builder(baseUrl: serviceEndpoints.sdkEndpoint, path: "evaluations", defaultQueryString: queryString)
            .set(method: .post)
            .add(header: "Content-Type", withValue: "application/json")
            .add(header: "Authorization", withValue: "Bearer \(token)")
            .build()
        
        let body = serializeAttributes(["attributes":target.attributes])
        return try await retryableHttpClient.execute(endpoint, category: .evaluations, body: body)
    }

    private func serializeAttributes(_ attributes: [String: Any]?) -> Data? {
        guard let attributes, !attributes.isEmpty else {
            return "{}".data(using: .utf8)
        }
        return try? JSONSerialization.data(withJSONObject: attributes)
    }
}
