import Foundation
import Logging

protocol TreatmentsManager: Sendable {
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult
    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]
}

final class DefaultTreatmentsManager: TreatmentsManager, @unchecked Sendable {

    private let target: Target
    private let secureHttpClient: SecureHttpClient
    private let splitManager: DefaultSplitManager?

    private var cachedEvaluations = [String: EvaluationResult]()
    private let lock = NSLock()

    init(target: Target, secureHttpClient: SecureHttpClient, splitManager: DefaultSplitManager? = nil) {
        self.target = target
        self.secureHttpClient = secureHttpClient
        self.splitManager = splitManager
    }

    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult {
        if let cached = getCachedEvaluation(for: flag) {
            return cached
        }

        do {
            let filters = EvaluationFilters(flagNames: [flag])
            let response = try await secureHttpClient.fetchEvaluations(target: target, filters: filters)

            guard response.isSuccess, let data = response.data else {
                Logger.e("Failed to fetch treatment for flag '\(flag)': HTTP \(response.code)")
                return EvaluationResult(flag: flag, treatment: "control", flagSets: [])
            }

            let evaluationsResult = try Json.decode(from: data, to: EvaluationsResult.self)
            cacheEvaluations(evaluationsResult.evaluations)

            return getCachedEvaluation(for: flag) ?? EvaluationResult(flag: flag, treatment: "control", flagSets: [])
        } catch {
            Logger.e("Failed to fetch treatment for flag '\(flag)': \(error)")
            return EvaluationResult(flag: flag, treatment: "control", flagSets: [])
        }
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        do {
            let filters = EvaluationFilters(flagNames: flags)
            let response = try await secureHttpClient.fetchEvaluations(target: target, filters: filters)

            guard response.isSuccess, let data = response.data else {
                Logger.e("Failed to fetch treatments for flags \(flags): HTTP \(response.code)")
                return flags.map { EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
            }

            let evaluationsResult = try Json.decode(from: data, to: EvaluationsResult.self)
            cacheEvaluations(evaluationsResult.evaluations)

            return flags.compactMap { getCachedEvaluation(for: $0) }
        } catch {
            Logger.e("Failed to fetch treatments for flags \(flags): \(error)")
            return flags.map { EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
        }
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        do {
            let filters = EvaluationFilters(flagSets: flagSets)
            let response = try await secureHttpClient.fetchEvaluations(target: target, filters: filters)

            guard response.isSuccess, let data = response.data else {
                Logger.e("Failed to fetch treatments for flag sets \(flagSets): HTTP \(response.code)")
                return flagSets.map { EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
            }

            let evaluationsResult = try Json.decode(from: data, to: EvaluationsResult.self)
            cacheEvaluations(evaluationsResult.evaluations)

            return evaluationsResult.evaluations
        } catch {
            Logger.e("Failed to fetch treatments for flag sets \(flagSets): \(error)")
            return flagSets.map { EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
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
