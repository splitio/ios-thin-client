import XCTest
@testable import SplitThin

final class EvaluationChangeTest: XCTestCase {

    func testProperties() {
        let target = Target(matchingKey: "user1")
        let evals = [
            EvaluationResult(flag: "flag_a", treatment: "on"),
            EvaluationResult(flag: "flag_b", treatment: "off")
        ]
        let change = EvaluationChange(target: target, changeNumber: 99, evaluations: evals)

        XCTAssertEqual(change.target, target)
        XCTAssertEqual(change.changeNumber, 99)
        XCTAssertEqual(change.evaluations.count, 2)
        XCTAssertEqual(change.evaluations[0].flag, "flag_a")
        XCTAssertEqual(change.evaluations[1].flag, "flag_b")
    }

    func testEmptyEvaluations() {
        let change = EvaluationChange(target: Target(matchingKey: "user1"), changeNumber: 0, evaluations: [])

        XCTAssertTrue(change.evaluations.isEmpty)
    }
}
