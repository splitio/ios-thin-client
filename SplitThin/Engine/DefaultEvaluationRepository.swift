import Foundation
import Logging

public protocol EvaluationRepository: Sendable {
    func getTreatment(flag: String, target: Target) async -> EvaluationResult?
    func getTreatments(flags: [String], target: Target) async -> [EvaluationResult]
    func getTreatmentsByFlagSets(_ flagSets: [String], target: Target) async -> [EvaluationResult]
    func getFlagNames(target: Target) async -> [String]
    func setTarget(_ target: Target) async
    func update(_ evaluations: [EvaluationResult])
    func clear()
}

final class DefaultEvaluationRepository: EvaluationRepository, @unchecked Sendable {

    private let secureHttpClient: SecureHttpClient
    private let splitManager: DefaultSplitManager?

    private var currentTarget: Target
    private var cachedEvaluations = [String: EvaluationResult]()
    private let lock = NSLock()

    init(target: Target, secureHttpClient: SecureHttpClient, splitManager: DefaultSplitManager? = nil) {
        self.currentTarget = target
        self.secureHttpClient = secureHttpClient
        self.splitManager = splitManager
    }

    func getTreatment(flag: String, target: Target) async -> EvaluationResult? {
        if let cached = getCachedEvaluation(for: flag) {
            return cached
        }

        let evaluations = await fetchEvaluations(target: target, filters: EvaluationFilters(flagNames: [flag]))
        return evaluations.first
    }

    func getTreatments(flags: [String], target: Target) async -> [EvaluationResult] {
        let cachedResults = flags.compactMap { getCachedEvaluation(for: $0) }
        if cachedResults.count == flags.count {
            return cachedResults
        }

        return await fetchEvaluations(target: target, filters: EvaluationFilters(flagNames: flags))
    }

    func getTreatmentsByFlagSets(_ flagSets: [String], target: Target) async -> [EvaluationResult] {
        await fetchEvaluations(target: target, filters: EvaluationFilters(flagSets: flagSets))
    }

    func getFlagNames(target: Target) async -> [String] {
        withLock(lock) { Array(cachedEvaluations.keys) }
    }

    func setTarget(_ target: Target) async {
        withLock(lock) {
            currentTarget = target
            cachedEvaluations.removeAll()
        }
    }

    func update(_ evaluations: [EvaluationResult]) {
        cacheEvaluations(evaluations)
    }

    func clear() {
        withLock(lock) { cachedEvaluations.removeAll() }
    }

    // MARK: - Private

    private func fetchEvaluations(target: Target, filters: EvaluationFilters?) async -> [EvaluationResult] {
        do {
            let response = try await secureHttpClient.fetchEvaluations(target: target, filters: filters)

            guard response.isSuccess, let data = response.data else {
                Logger.e("Failed to fetch evaluations: HTTP \(response.code)")
                return []
            }

            let evaluationsResult = try Json.decode(from: data, to: EvaluationsResult.self)
            cacheEvaluations(evaluationsResult.evaluations)

            return evaluationsResult.evaluations
        } catch {
            Logger.e("Failed to fetch evaluations: \(error)")
            return []
        }
    }

    private func getCachedEvaluation(for flag: String) -> EvaluationResult? {
        withLock(lock) { cachedEvaluations[flag] }
    }

    private func cacheEvaluations(_ evaluations: [EvaluationResult]) {
        withLock(lock) {
            for evaluation in evaluations {
                cachedEvaluations[evaluation.flag] = evaluation
            }
            splitManager?.updateFlags(evaluations.map { $0.flag })
        }
    }
}
