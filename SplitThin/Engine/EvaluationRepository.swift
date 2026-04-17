import Foundation
import Logging

protocol EvaluationRepository: Sendable {
    func getEvaluation(flag: String, target: Target) -> StoredEvaluation?
    func getEvaluations(flags: [String], target: Target) -> [StoredEvaluation]
    func getEvaluationsByFlagSets(_ flagSets: [String], target: Target) -> [StoredEvaluation]
    func getFlagNames(target: Target) -> [String]
    func setTarget(_ target: Target)
    func initialize(target: Target) async throws
}

final class DefaultEvaluationRepository: EvaluationRepository, @unchecked Sendable {

    private let fetchCoordinator: EvaluationFetchCoordinator
    private let evaluationFilters: EvaluationFilters?
    private let storage: InMemoryEvaluationStorage

    init(fetchCoordinator: EvaluationFetchCoordinator, storage: InMemoryEvaluationStorage, evaluationFilters: EvaluationFilters?) {
        self.fetchCoordinator = fetchCoordinator
        self.storage = storage
        self.evaluationFilters = evaluationFilters
    }

    func getEvaluation(flag: String, target: Target) -> StoredEvaluation? {
        storage.getEvaluation(flag: flag, target: target)
    }

    func getEvaluations(flags: [String], target: Target) -> [StoredEvaluation] {
        storage.getEvaluations(flags: flags, target: target)
    }

    func getEvaluationsByFlagSets(_ flagSets: [String], target: Target) -> [StoredEvaluation] {
        storage.getEvaluationsByFlagSets(flagSets, target: target)
    }

    func getFlagNames(target: Target) -> [String] {
        storage.getFlagNames(target: target)
    }

    func setTarget(_ target: Target) {
        Task { [weak self] in
            guard let self else { return }
            await self.storage.clear(target: target)
            if let evaluations = await self.fetchCoordinator.fetchIfNeeded(target: target, filters: self.evaluationFilters, reason: .targetSwitch) {
                self.storage.cacheEvaluations(evaluations, for: target)
            } else {
                Logger.e("EvaluationRepository: Failed to fetch evaluations for target \(target.matchingKey)")
            }
        }
    }

    func initialize(target: Target) async throws {
        guard let evaluations = await fetchCoordinator.fetchIfNeeded(target: target, filters: evaluationFilters, reason: .initialization) else {
            throw EvaluationFetchError.fetchFailed
        }
        storage.cacheEvaluations(evaluations, for: target)
    }

}
