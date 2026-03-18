import Foundation
import Logging

final class DefaultTreatmentsManager: TreatmentsManager, @unchecked Sendable {

    private let secureHttpClient: SecureHttpClient
    private let config: SplitClientConfig

    private var sdkEndpoint: URL {
        config.serviceEndpoints?.sdkEndpoint ?? URL(string: "https://sdk.split.io/api")!
    }

    init(secureHttpClient: SecureHttpClient, config: SplitClientConfig) {
        self.secureHttpClient = secureHttpClient
        self.config = config
    }

    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult {
        do {
            let result: EvaluationResult = try await secureHttpClient.get(
                url: sdkEndpoint,
                path: "treatments/\(flag)"
            )
            return result
        } catch {
            Logger.e("Failed to fetch treatment for flag '\(flag)': \(error)")
            return EvaluationResult(flag: flag, treatment: "control")
        }
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        do {
            let results: [EvaluationResult] = try await secureHttpClient.getArray(
                url: sdkEndpoint,
                path: "treatments"
            )
            return results
        } catch {
            Logger.e("Failed to fetch treatments for flags \(flags): \(error)")
            return flags.map { EvaluationResult(flag: $0, treatment: "control") }
        }
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        do {
            let results: [EvaluationResult] = try await secureHttpClient.getArray(
                url: sdkEndpoint,
                path: "treatments/flagsets"
            )
            return results
        } catch {
            Logger.e("getTreatmentsByFlagSets: Failed to fetch treatments for flag sets \(flagSets): \(error)")
            return flagSets.map { EvaluationResult(flag: $0, treatment: "control") }
        }
    }
}
