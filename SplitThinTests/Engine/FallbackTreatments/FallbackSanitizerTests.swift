import XCTest
@testable import SplitThin

final class FallbackSanitizerTests: XCTestCase {

    // MARK: - Treatment validation

    func testValidTreatmentIsAccepted() {
        let result = FallbackSanitizer.sanitize(treatment: FallbackTreatment(treatment: "GLOBAL_DEFAULT"))

        XCTAssertEqual(result?.treatment, "GLOBAL_DEFAULT")
    }

    func testTreatmentWithSpacesIsRejected() {
        let result = FallbackSanitizer.sanitize(treatment: FallbackTreatment(treatment: "GLOBAL DEFAULT"))

        XCTAssertNil(result)
    }

    func testTreatmentTooLongIsRejected() {
        let longName = String(repeating: "a", count: 101)
        let result = FallbackSanitizer.sanitize(treatment: FallbackTreatment(treatment: longName))

        XCTAssertNil(result)
    }

    func testTreatmentAtMaxLengthIsAccepted() {
        let maxName = String(repeating: "a", count: 100)
        let result = FallbackSanitizer.sanitize(treatment: FallbackTreatment(treatment: maxName))

        XCTAssertEqual(result?.treatment, maxName)
    }

    func testTreatmentStartingWithDigitAndDotIsAccepted() {
        let result = FallbackSanitizer.sanitize(treatment: FallbackTreatment(treatment: "123.treatment"))

        XCTAssertEqual(result?.treatment, "123.treatment")
    }

    func testTreatmentStartingWithLetterAndDotDigitIsRejected() {
        let result = FallbackSanitizer.sanitize(treatment: FallbackTreatment(treatment: "treatment.23"))

        XCTAssertNil(result)
    }

    func testTreatmentWithHyphenAndUnderscoreIsAccepted() {
        let result = FallbackSanitizer.sanitize(treatment: FallbackTreatment(treatment: "my-treatment_v2"))

        XCTAssertEqual(result?.treatment, "my-treatment_v2")
    }

    // MARK: - Flag name validation

    func testFlagNameWithSpacesIsRejected() {
        let byFlag = ["flag name": FallbackTreatment(treatment: "on")]
        let result = FallbackSanitizer.sanitize(byFlagFallbacks: byFlag)

        XCTAssertTrue(result.isEmpty)
    }

    func testFlagNameTooLongIsRejected() {
        let longFlag = String(repeating: "f", count: 101)
        let byFlag = [longFlag: FallbackTreatment(treatment: "on")]
        let result = FallbackSanitizer.sanitize(byFlagFallbacks: byFlag)

        XCTAssertTrue(result.isEmpty)
    }

    func testFlagNameAtMaxLengthIsAccepted() {
        let maxFlag = String(repeating: "f", count: 100)
        let byFlag = [maxFlag: FallbackTreatment(treatment: "on")]
        let result = FallbackSanitizer.sanitize(byFlagFallbacks: byFlag)

        XCTAssertEqual(result[maxFlag]?.treatment, "on")
    }

    // MARK: - Mixed valid and invalid

    func testByFlagSanitizationFiltersMixedEntries() {
        let byFlag = [
            "flag1": FallbackTreatment(treatment: "FLAG1_TREATMENT"),
            "flag2": FallbackTreatment(treatment: "treatment.23"),
            "flag3": FallbackTreatment(treatment: "FLAG3_ TREATMENT"),
            "flag4": FallbackTreatment(treatment: "123.treatment")
        ]

        let result = FallbackSanitizer.sanitize(byFlagFallbacks: byFlag)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result["flag1"]?.treatment, "FLAG1_TREATMENT")
        XCTAssertEqual(result["flag4"]?.treatment, "123.treatment")
        XCTAssertNil(result["flag2"])
        XCTAssertNil(result["flag3"])
    }

    func testNonExistentFlagReturnsNil() {
        let byFlag = ["flag": FallbackTreatment(treatment: "FLAG1_TREATMENT")]
        let result = FallbackSanitizer.sanitize(byFlagFallbacks: byFlag)

        XCTAssertNil(result["otherFlag"])
    }
}
