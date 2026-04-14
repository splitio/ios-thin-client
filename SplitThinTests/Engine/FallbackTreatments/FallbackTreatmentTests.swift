import XCTest
@testable import SplitThin

final class FallbackTreatmentTests: XCTestCase {

    // MARK: - ExpressibleByStringLiteral
    func testStringLiteralCreatesTreatmentWithoutConfig() {
        let fallback: FallbackTreatment = "my_treatment"

        XCTAssertEqual(fallback.treatment, "my_treatment")
        XCTAssertNil(fallback.config)
    }

    func testMixedDictionaryWithStringLiteralsAndFallbackTreatments() {
        let byFlag: [String: FallbackTreatment] = [
            "flag1": "simple_treatment",
            "flag2": FallbackTreatment(treatment: "with_config", config: "{\"key\":true}")
        ]

        XCTAssertEqual(byFlag["flag1"]?.treatment, "simple_treatment")
        XCTAssertNil(byFlag["flag1"]?.config)
        XCTAssertEqual(byFlag["flag2"]?.treatment, "with_config")
        XCTAssertEqual(byFlag["flag2"]?.config, "{\"key\":true}")
    }
}
