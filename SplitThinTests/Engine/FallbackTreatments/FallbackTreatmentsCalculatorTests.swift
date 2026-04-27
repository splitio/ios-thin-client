import XCTest
@testable import SplitThin

final class FallbackTreatmentsCalculatorTests: XCTestCase {

    func testResolveReturnsByFlagFallback() {
        let config = FallbackTreatmentsConfig.builder()
                                             .global(FallbackTreatment(treatment: "global"))
                                             .byFlag(["flag1": FallbackTreatment(treatment: "t1")])
                                             .build()
        let calculator = DefaultFallbackTreatmentsCalculator(fallbacksConfig: config)

        let result = calculator.resolve(flagName: "flag1", label: "testLabel")

        XCTAssertEqual(result.treatment, "t1")
        XCTAssertEqual(result.label, "fallback - testLabel")
    }

    func testResolveReturnsGlobalFallbackIfFlagMissing() {
        let config = FallbackTreatmentsConfig.builder()
                                             .global(FallbackTreatment(treatment: "global"))
                                             .build()
        let calculator = DefaultFallbackTreatmentsCalculator(fallbacksConfig: config)

        let result = calculator.resolve(flagName: "unknownFlag", label: "testLabel")

        XCTAssertEqual(result.treatment, "global")
        XCTAssertEqual(result.label, "fallback - testLabel")
    }

    func testResolveReturnsControlIfNoFallbacks() {
        let config = FallbackTreatmentsConfig.builder().build()
        let calculator = DefaultFallbackTreatmentsCalculator(fallbacksConfig: config)

        let result = calculator.resolve(flagName: "anyFlag", label: "testLabel")

        XCTAssertEqual(result.treatment, "control")
        XCTAssertEqual(result.label, "testLabel")
    }

    func testResolveWithNilLabel() {
        let config = FallbackTreatmentsConfig.builder()
                                             .byFlag(["flag1": FallbackTreatment(treatment: "t1")])
                                             .build()
        let calculator = DefaultFallbackTreatmentsCalculator(fallbacksConfig: config)

        let result = calculator.resolve(flagName: "flag1", label: nil)

        XCTAssertEqual(result.treatment, "t1")
        XCTAssertNil(result.label)
    }

    func testByFlagOverridesGlobal() {
        let globalFallback = FallbackTreatment(treatment: "global_treatment", config: "{\"from\":\"global\"}")
        let flagFallback = FallbackTreatment(treatment: "flag_treatment", config: "{\"from\":\"flag\"}")
        let config = FallbackTreatmentsConfig.builder()
                                             .global(globalFallback)
                                             .byFlag(["flag1": flagFallback])
                                             .build()
        let calculator = DefaultFallbackTreatmentsCalculator(fallbacksConfig: config)

        let result = calculator.resolve(flagName: "flag1", label: "lbl")

        XCTAssertEqual(result.treatment, "flag_treatment")
        XCTAssertEqual(result.config, "{\"from\":\"flag\"}")
    }

    func testGlobalConfigIsPropagated() {
        let config = FallbackTreatmentsConfig.builder()
                                             .global(FallbackTreatment(treatment: "on", config: "{\"key\":true}"))
                                             .build()
        let calculator = DefaultFallbackTreatmentsCalculator(fallbacksConfig: config)

        let result = calculator.resolve(flagName: "someFlag", label: nil)

        XCTAssertEqual(result.treatment, "on")
        XCTAssertEqual(result.config, "{\"key\":true}")
    }

    func testControlHasNoConfig() {
        let config = FallbackTreatmentsConfig.builder().build()
        let calculator = DefaultFallbackTreatmentsCalculator(fallbacksConfig: config)

        let result = calculator.resolve(flagName: "flag", label: nil)

        XCTAssertEqual(result.treatment, "control")
        XCTAssertNil(result.config)
    }
}
