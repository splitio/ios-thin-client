//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Http
import BackoffCounter

protocol RetryableHttpClient: Sendable {
    func execute(_ endpoint: Endpoint, category: RequestCategory, body: Data?) async throws -> HttpResponse
}

extension RetryableHttpClient {
    func execute(_ endpoint: Endpoint, category: RequestCategory) async throws -> HttpResponse {
        try await execute(endpoint, category: category, body: nil)
    }
}

enum RetryableHttpError: Error {
    case maxAttemptsReached(statusCode: Int, attempts: Int)
    case networkError(Error)
    case cancelled
}

final class DefaultRetryableHttpClient: RetryableHttpClient, @unchecked Sendable {

    private let httpClient: HttpClient
    private let observer: Observer // For logging & telemetry
    private let policies: RetryPoliciesByCategory
    private let backoffCounterFactory: (Int) -> BackoffCounter

    init(httpClient: HttpClient, observer: Observer, policies: RetryPoliciesByCategory? = nil, backoffCounterFactory: @escaping (Int) -> BackoffCounter = { DefaultBackoffCounter(backoffBase: $0) }) {
        self.httpClient = httpClient
        self.observer = observer
        self.policies = policies ?? Self.defaultPolicies()
        self.backoffCounterFactory = backoffCounterFactory
    }

    func execute(_ endpoint: Endpoint, category: RequestCategory, body: Data?) async throws -> HttpResponse {
        observer.notify(event: .httpRequestStarted(category: category.toHttpCategory, method: endpoint.method == .post ? .post : .get))

        let categoryPolicies = policies[category] ?? CategoryRetryPolicies()
        let backoffCounter = backoffCounterFactory(Int(categoryPolicies.fallback?.backoffBaseSeconds ?? 1))
        backoffCounter.resetCounter()

        var attempt = 0

        while true {
            try Task.checkCancellation()

            let response = try await performRequest(endpoint: endpoint, body: body)

            if response.isSuccess {
                observer.notify(event: .httpRequestSucceeded(category: category.toHttpCategory, statusCode: response.code))
                return response
            }

            let statusCode = response.code
            guard let policy = categoryPolicies.policy(for: statusCode) else {
                observer.notify(event: .httpRequestFailedNonRetryable(category: category.toHttpCategory, statusCode: statusCode))
                return response
            }

            attempt += 1
            if policy.maxAttempts != -1 && attempt >= policy.maxAttempts {
                observer.notify(event: .httpRetryExhausted(category: category.toHttpCategory, statusCode: statusCode))
                throw RetryableHttpError.maxAttemptsReached(statusCode: statusCode, attempts: attempt)
            }

            observer.notify(event: .httpRequestFailedRetryable(category: category.toHttpCategory, statusCode: statusCode))

            let waitTime = backoffCounter.getNextRetryTime()
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
    }

    private func performRequest(endpoint: Endpoint, body: Data?) async throws -> HttpResponse {
        try await withCheckedThrowingContinuation { continuation in
            do {
                _ = try httpClient.sendRequest(endpoint: endpoint, parameters: nil, headers: endpoint.headers, body: body)
                    .getResponse { response in
                        continuation.resume(returning: response)
                    } errorHandler: { error in
                        continuation.resume(throwing: RetryableHttpError.networkError(error))
                    }
            } catch {
                continuation.resume(throwing: RetryableHttpError.networkError(error))
            }
        }
    }

    private static func defaultPolicies() -> RetryPoliciesByCategory {
        let defaultPolicy = RetryPolicy(maxAttempts: 3, backoffBaseSeconds: 1.0)
        let defaultCategoryPolicies = CategoryRetryPolicies(
            fallback: defaultPolicy,
            byStatus: [
                400: nil,
                401: nil,
                403: nil,
                404: nil
            ]
        )

        return [
            .evaluations: defaultCategoryPolicies,
            .events: defaultCategoryPolicies,
            .telemetry: defaultCategoryPolicies,
            .auth: defaultCategoryPolicies
        ]
    }
}
