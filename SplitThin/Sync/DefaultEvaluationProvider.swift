import Foundation
import Logging

protocol EvaluationProvider: Sendable {
    func fetchAndUpdate(target: Target, filters: EvaluationFilters?) async
}

final class DefaultEvaluationProvider: EvaluationProvider, @unchecked Sendable {

    private let secureHttpClient: SecureHttpClient
    private let evaluationRepository: EvaluationRepository

    init(secureHttpClient: SecureHttpClient, evaluationRepository: EvaluationRepository) {
        self.secureHttpClient = secureHttpClient
        self.evaluationRepository = evaluationRepository
    }

    func fetchAndUpdate(target: Target, filters: EvaluationFilters?) async {

        do {
            let response = try await secureHttpClient.fetchEvaluations(target: target, filters: filters)

            guard response.isSuccess, let data = response.data else {
                Logger.e("EvaluationProvider: Failed to fetch evaluations: HTTP \(response.code)")
                return
            }

            let evaluationsResult = try Json.decode(from: data, to: EvaluationsResult.self)
            evaluationRepository.update(evaluationsResult.evaluations)

            Logger.d("EvaluationProvider: Updated \(evaluationsResult.evaluations.count) evaluations")
        } catch {
            Logger.e("EvaluationProvider: Failed to fetch evaluations: \(error)")
        }
    }
}
