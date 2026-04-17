import XCTest
@testable import SplitThin

final class InMemoryEvaluationStorageTests: XCTestCase {

    private var storage: InMemoryEvaluationStorage!
    private let target = Target(matchingKey: "user1")

    override func setUp() {
        super.setUp()
        storage = InMemoryEvaluationStorage()
    }

    func testUpsertStoresEvaluations() async throws {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        let change = EvaluationChange(target: target, changeNumber: 1, evaluations: evaluations)

        try await storage.upsert(change: change)

        XCTAssertEqual(storage.getEvaluation(flag: "flag1", target: target)?.evaluationResult.treatment, "on")
    }

    func testUpsertOverwritesExistingEvaluation() async throws {
        let eval1 = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        let eval2 = [EvaluationResult(flag: "flag1", treatment: "off", flagSets: [])]

        try await storage.upsert(change: EvaluationChange(target: target, changeNumber: 1, evaluations: eval1))
        try await storage.upsert(change: EvaluationChange(target: target, changeNumber: 2, evaluations: eval2))

        XCTAssertEqual(storage.getEvaluation(flag: "flag1", target: target)?.evaluationResult.treatment, "off")
    }

    func testClearTargetRemovesItsEvaluations() async throws {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        try await storage.upsert(change: EvaluationChange(target: target, changeNumber: 1, evaluations: evaluations))

        await storage.clear(target: target)

        XCTAssertNil(storage.getEvaluation(flag: "flag1", target: target))
    }

    func testClearTargetDoesNotAffectOtherTargets() async throws {
        let target2 = Target(matchingKey: "user2")
        let evals1 = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        let evals2 = [EvaluationResult(flag: "flag1", treatment: "off", flagSets: [])]
        try await storage.upsert(change: EvaluationChange(target: target, changeNumber: 1, evaluations: evals1))
        try await storage.upsert(change: EvaluationChange(target: target2, changeNumber: 1, evaluations: evals2))

        await storage.clear(target: target)

        XCTAssertNil(storage.getEvaluation(flag: "flag1", target: target))
        XCTAssertEqual(storage.getEvaluation(flag: "flag1", target: target2)?.evaluationResult.treatment, "off")
    }

    func testGetEvaluationsReturnsRequestedFlags() async throws {
        let evaluations = [
            EvaluationResult(flag: "flag1", treatment: "on", flagSets: []),
            EvaluationResult(flag: "flag2", treatment: "off", flagSets: [])
        ]
        try await storage.upsert(change: EvaluationChange(target: target, changeNumber: 1, evaluations: evaluations))

        let result = storage.getEvaluations(flags: ["flag1"], target: target)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.evaluationResult.treatment, "on")
    }

    func testGetEvaluationsByFlagSetsReturnsMatchingEvaluations() async throws {
        let evaluations = [
            EvaluationResult(flag: "flag1", treatment: "on", flagSets: ["setA"]),
            EvaluationResult(flag: "flag2", treatment: "off", flagSets: ["setB"])
        ]
        try await storage.upsert(change: EvaluationChange(target: target, changeNumber: 1, evaluations: evaluations))

        let result = storage.getEvaluationsByFlagSets(["setA"], target: target)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.evaluationResult.treatment, "on")
    }

    func testGetFlagNamesReturnsAllCachedFlags() async throws {
        let evaluations = [
            EvaluationResult(flag: "flag1", treatment: "on", flagSets: []),
            EvaluationResult(flag: "flag2", treatment: "off", flagSets: [])
        ]
        try await storage.upsert(change: EvaluationChange(target: target, changeNumber: 1, evaluations: evaluations))

        let names = storage.getFlagNames(target: target)

        XCTAssertEqual(Set(names), ["flag1", "flag2"])
    }
}
