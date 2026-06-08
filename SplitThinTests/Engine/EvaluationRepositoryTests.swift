import XCTest
@testable import SplitThin

final class EvaluationRepositoryTests: XCTestCase {

    private var repository: DefaultEvaluationRepository!
    private let target = Target(matchingKey: "user1", trafficType: "user")

    override func setUp() {
        super.setUp()
        repository = DefaultEvaluationRepository(fetchCoordinator: EvaluationFetchCoordinatorMock(), evaluationFilters: nil)
    }

    override func tearDown() {
        repository = nil
        super.tearDown()
    }

    // MARK: - getEvaluationsByFlagSets

    func testReturnsFlagsMatchingTheRequestedSet() {
        repository.update([
            EvaluationResult(flag: "flag1", treatment: "on", flagSets: ["set-a"]),
            EvaluationResult(flag: "flag2", treatment: "on", flagSets: ["set-a"])
        ], for: target)

        let flags = repository.getEvaluationsByFlagSets(["set-a"], target: target).map { $0.evaluationResult.flag }.sorted()

        XCTAssertEqual(flags, ["flag1", "flag2"])
    }

    func testExcludesFlagsNotInTheRequestedSet() {
        repository.update([
            EvaluationResult(flag: "flag1", treatment: "on", flagSets: ["set-a"]),
            EvaluationResult(flag: "flag2", treatment: "on", flagSets: ["set-b"])
        ], for: target)

        let flags = repository.getEvaluationsByFlagSets(["set-a"], target: target).map { $0.evaluationResult.flag }.sorted()

        XCTAssertEqual(flags, ["flag1"])
    }

    func testReturnsFlagOnPartialSetOverlap() {
        repository.update([
            EvaluationResult(flag: "flag1", treatment: "on", flagSets: ["set-a", "set-b"])
        ], for: target)

        // Requested ["set-b", "set-c"] overlaps on set-b.
        let flags = repository.getEvaluationsByFlagSets(["set-b", "set-c"], target: target).map { $0.evaluationResult.flag }.sorted()

        XCTAssertEqual(flags, ["flag1"])
    }

    func testExcludesFlagWithEmptySets() {
        repository.update([
            EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])
        ], for: target)

        let flags = repository.getEvaluationsByFlagSets(["set-a"], target: target).map { $0.evaluationResult.flag }.sorted()

        XCTAssertEqual(flags, [])
    }

    func testReturnsEmptyWhenNoSetMatches() {
        repository.update([
            EvaluationResult(flag: "flag1", treatment: "on", flagSets: ["set-a"]),
            EvaluationResult(flag: "flag2", treatment: "on", flagSets: ["set-b"])
        ], for: target)

        let flags = repository.getEvaluationsByFlagSets(["set-z"], target: target).map { $0.evaluationResult.flag }.sorted()

        XCTAssertEqual(flags, [])
    }

    func testIsolatesByTarget() {
        let otherTarget = Target(matchingKey: "user2", trafficType: "user")
        repository.update([
            EvaluationResult(flag: "flag1", treatment: "on", flagSets: ["set-a"])
        ], for: target)

        XCTAssertEqual(repository.getEvaluationsByFlagSets(["set-a"], target: otherTarget).count, 0)
    }
}
