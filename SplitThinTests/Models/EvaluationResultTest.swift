import XCTest
@testable import SplitThin

final class EvaluationResultTest: XCTestCase {

    func testAllProperties() {
        let result = EvaluationResult(flag: "feature_x", treatment: "on", label: "in segment all", changeNumber: 12345)

        XCTAssertEqual(result.flag, "feature_x")
        XCTAssertEqual(result.treatment, "on")
        XCTAssertEqual(result.label, "in segment all")
        XCTAssertEqual(result.changeNumber, 12345)
    }

    func testDefaults() {
        let result = EvaluationResult(flag: "feature_x", treatment: "off")

        XCTAssertEqual(result.flag, "feature_x")
        XCTAssertEqual(result.treatment, "off")
        XCTAssertNil(result.label)
        XCTAssertNil(result.changeNumber)
    }
}
