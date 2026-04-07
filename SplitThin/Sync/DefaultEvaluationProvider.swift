import Foundation
import Logging

protocol EvaluationProvider: Sendable {
    func fetch(target: Target, filters: EvaluationFilters?) async -> EvaluationChange?
}

final class DefaultEvaluationProvider: EvaluationProvider, @unchecked Sendable {

    private let secureHttpClient: SecureHttpClient

    init(secureHttpClient: SecureHttpClient) {
        self.secureHttpClient = secureHttpClient
    }

    func fetch(target: Target, filters: EvaluationFilters?) async -> EvaluationChange? {
        do {
            let response = try await secureHttpClient.fetchEvaluations(target: target, filters: filters)

            guard response.isSuccess, let data = response.data else {
                Logger.e("EvaluationProvider: Failed to fetch evaluations: HTTP \(response.code)")
                return nil
            }

            let result = try Json.decode(from: data, to: EvaluationsResult.self)
            let changeNumber = result.till ?? -1

            Logger.d("EvaluationProvider: Fetched \(result.evaluations.count) evaluations")

            return EvaluationChange(target: target, changeNumber: changeNumber, evaluations: result.evaluations)
        } catch {
            Logger.e("EvaluationProvider: Failed to fetch evaluations: \(error)")
            return nil
        }
    }
}
