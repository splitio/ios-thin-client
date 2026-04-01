import Foundation

public protocol EvaluationRepository: Sendable {
    func getTreatment(flag: String, target: Target) -> EvaluationResult?
    func getTreatments(flags: [String], target: Target) -> [EvaluationResult]
    func getTreatmentsByFlagSets(_ flagSets: [String], target: Target) -> [EvaluationResult]
    func getFlagNames(target: Target) -> [String]
    func setTarget(_ target: Target)
    func initialize(target: Target) async
}

final class DefaultEvaluationRepository: EvaluationRepository, @unchecked Sendable {

    private let fetchCoordinator: EvaluationFetchCoordinator
    private let evaluationFilters: EvaluationFilters?
    private let storage: EvaluationReadStorage?

    private var cache = [Target: [String: EvaluationResult]]()
    private let lock = NSLock()

    init(fetchCoordinator: EvaluationFetchCoordinator, evaluationFilters: EvaluationFilters?, storage: EvaluationReadStorage? = nil) {
        self.fetchCoordinator = fetchCoordinator
        self.evaluationFilters = evaluationFilters
        self.storage = storage
    }

    func getTreatment(flag: String, target: Target) -> EvaluationResult? {
        withLock(lock) { cache[target]?[flag] }
    }

    func getTreatments(flags: [String], target: Target) -> [EvaluationResult] {
        withLock(lock) {
            let targetCache = cache[target] ?? [:]
            return flags.compactMap { targetCache[$0] }
        }
    }

    func getTreatmentsByFlagSets(_ flagSets: [String], target: Target) -> [EvaluationResult] {
        withLock(lock) {
            let targetCache = cache[target] ?? [:]
            return targetCache.values.filter { evaluation in
                !Set(evaluation.flagSets).isDisjoint(with: flagSets)
            }
        }
    }

    func getFlagNames(target: Target) -> [String] {
        withLock(lock) { Array(cache[target]?.keys ?? [String: EvaluationResult]().keys) }
    }

    func setTarget(_ target: Target) {
        withLock(lock) {
            cache[target] = nil
        }
        
        Task { [weak self] in
            guard let self else { return }
            let evaluations = await self.fetchCoordinator.fetchIfNeeded(target: target, filters: self.evaluationFilters, reason: .targetSwitch)
            self.cacheEvaluations(evaluations, for: target)
        }
    }

    func initialize(target: Target) async {
        await loadFromStorageIfNeeded(target: target)
        let evaluations = await fetchCoordinator.fetchIfNeeded(target: target, filters: evaluationFilters, reason: .initialization)
        cacheEvaluations(evaluations, for: target)
    }

    func clear() {
        withLock(lock) { cache.removeAll() }
    }

    // MARK: - Private
    private func loadFromStorageIfNeeded(target: Target) async {
        guard let storage else { return }
        let flagNames = await storage.getFlagNames(target: target)
        guard !flagNames.isEmpty else { return }
        let cached = await storage.get(flags: flagNames, target: target)
        cacheEvaluations(cached, for: target)
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
