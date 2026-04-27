import Foundation

protocol FallbackTreatmentsCalculator: Sendable {
    func resolve(flagName: String, label: String?) -> FallbackTreatment
}

final class DefaultFallbackTreatmentsCalculator: FallbackTreatmentsCalculator {

    private let labelPrefix = "fallback - "
    private let control = "control"
    private let fallbacks: FallbackTreatmentsConfig

    init(fallbacksConfig: FallbackTreatmentsConfig) {
        fallbacks = fallbacksConfig
    }

    func resolve(flagName: String, label: String?) -> FallbackTreatment {
        if let flagTreatment = fallbacks.byFlag[flagName] {
            return copyWithLabel(flagTreatment, label: resolveLabel(label))
        }

        if let clientFallback = fallbacks.global {
            return copyWithLabel(clientFallback, label: resolveLabel(label))
        }

        return FallbackTreatment(treatment: control, config: nil, label: label)
    }

    private func resolveLabel(_ label: String?) -> String? {
        guard let lbl = label else { return nil }
        return "\(labelPrefix)\(lbl)"
    }

    private func copyWithLabel(_ fallback: FallbackTreatment, label: String?) -> FallbackTreatment {
        FallbackTreatment(treatment: fallback.treatment, config: fallback.config, label: label)
    }
}
