import XCTest
@testable import SplitThin

final class EvaluationFiltersTest: XCTestCase {

    func testAllProperties() {
        let filters = EvaluationFilters(flagNames: ["flag_a", "flag_b"], flagSets: ["set_1"], withDynamicConfig: true)

        XCTAssertEqual(filters.flagNames, ["flag_a", "flag_b"])
        XCTAssertEqual(filters.flagSets, ["set_1"])
        XCTAssertTrue(filters.withDynamicConfig)
    }

    func testDefaults() {
        let filters = EvaluationFilters()

        XCTAssertNil(filters.flagNames)
        XCTAssertNil(filters.flagSets)
        XCTAssertFalse(filters.withDynamicConfig)
    }

    func testPartialInit() {
        let filters = EvaluationFilters(flagNames: ["flag_a"])

        XCTAssertEqual(filters.flagNames, ["flag_a"])
        XCTAssertNil(filters.flagSets)
        XCTAssertFalse(filters.withDynamicConfig)
    }
}
