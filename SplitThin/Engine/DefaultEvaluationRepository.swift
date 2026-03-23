import Foundation

public protocol EvaluationRepository: Sendable {
    func getTreatment(flag: String, target: Target) async -> EvaluationResult?
    func getTreatments(flags: [String], target: Target) async -> [EvaluationResult]
    func getTreatmentsByFlagSets(_ flagSets: [String], target: Target) async -> [EvaluationResult]
    func getFlagNames(target: Target) async -> [String]
    func setTarget(_ target: Target) async
    func initialize(target: Target) async
}

final class DefaultEvaluationRepository: EvaluationRepository, @unchecked Sendable {

    private let fetchCoordinator: EvaluationFetchCoordinator
    private let evaluationFilters: EvaluationFilters?

    private var cache = [Target: [String: EvaluationResult]]()
    private let lock = NSLock()

    init(fetchCoordinator: EvaluationFetchCoordinator, evaluationFilters: EvaluationFilters?) {
        self.fetchCoordinator = fetchCoordinator
        self.evaluationFilters = evaluationFilters
    }

    func getTreatment(flag: String, target: Target) async -> EvaluationResult? {
        await checkIfFetchOngoing(for: target)
        return withLock(lock) { cache[target]?[flag] }
    }

    func getTreatments(flags: [String], target: Target) async -> [EvaluationResult] {
        await checkIfFetchOngoing(for: target)
        return withLock(lock) {
            let targetCache = cache[target] ?? [:]
            return flags.compactMap { targetCache[$0] }
        }
    }

    func getTreatmentsByFlagSets(_ flagSets: [String], target: Target) async -> [EvaluationResult] {
        await checkIfFetchOngoing(for: target)
        return withLock(lock) {
            let targetCache = cache[target] ?? [:]
            return targetCache.values.filter { evaluation in
                !Set(evaluation.flagSets).isDisjoint(with: flagSets)
            }
        }
    }

    func getFlagNames(target: Target) async -> [String] {
        await checkIfFetchOngoing(for: target)
        return withLock(lock) { Array(cache[target]?.keys ?? [String: EvaluationResult]().keys) }
    }

    func setTarget(_ target: Target) async {
        await checkIfFetchOngoing(for: target)
        
        withLock(lock) {
            cache[target] = nil
        }
        
        let evaluations = await fetchCoordinator.fetchIfNeeded(target: target, filters: evaluationFilters, reason: .targetSwitch)
        cacheEvaluations(evaluations, for: target)
    }

    func initialize(target: Target) async {
        let evaluations = await fetchCoordinator.fetchIfNeeded(target: target, filters: evaluationFilters, reason: .initialization)
        cacheEvaluations(evaluations, for: target)
    }

    func clear() {
        withLock(lock) { cache.removeAll() }
    }

    // MARK: - Private
    private func checkIfFetchOngoing(for target: Target) async {
        if fetchCoordinator.hasInFlightFetch(for: target) {
            let evaluations = await fetchCoordinator.awaitInFlightFetch(for: target)
            cacheEvaluations(evaluations, for: target)
        }
    }

    private func cacheEvaluations(_ evaluations: [EvaluationResult], for target: Target) {
        guard !evaluations.isEmpty else { return }
        
        withLock(lock) {
            var targetCache = cache[target] ?? [:]
            for evaluation in evaluations {
                targetCache[evaluation.flag] = evaluation
            }
            cache[target] = targetCache
        }
    }
}
