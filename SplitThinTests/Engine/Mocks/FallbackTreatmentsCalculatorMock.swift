import Foundation
@testable import SplitThin

final class FallbackTreatmentsCalculatorMock: FallbackTreatmentsCalculator, @unchecked Sendable {

    var resolveResult: FallbackTreatment?
    var resolveCalls = [(flagName: String, label: String?)]()

    func resolve(flagName: String, label: String?) -> FallbackTreatment {
        resolveCalls.append((flagName: flagName, label: label))
        return resolveResult ?? FallbackTreatment(treatment: "control", config: nil, label: label)
    }
}
