import XCTest
@testable import SplitThin

final class DefaultEvaluationFetchCoordinatorTest: XCTestCase {

    private var provider: EvaluationProviderMock!
    private var coordinator: DefaultEvaluationFetchCoordinator!

    private let target = Target(matchingKey: "user1")
    private let filters = EvaluationFilters(flagNames: ["flag1"])

    override func setUp() {
        super.setUp()
        provider = EvaluationProviderMock()
        coordinator = DefaultEvaluationFetchCoordinator(provider: provider)
    }

    func testFetchReturnsEvaluations() async {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: ["set1"])]
        provider.resultToReturn = EvaluationsResult(since: -1, evaluations: evaluations, till: 100)

        let result = await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.flag, "flag1")
        XCTAssertEqual(provider.fetchCalls.count, 1)
    }

    func testFetchWithNilResultReturnsEmpty() async {
        provider.resultToReturn = nil

        let result = await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(provider.fetchCalls.count, 1)
    }

    func testConcurrentIdenticalRequestsAreDeduplicated() async {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)
        provider.fetchDelay = 200_000_000 // 200ms

        async let fetch1: [EvaluationResult] = coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms to ensure first fetch is in-flight
        async let fetch2: [EvaluationResult] = coordinator.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        let result1 = await fetch1
        let result2 = await fetch2

        XCTAssertEqual(result1.count, 1)
        XCTAssertEqual(result2.count, 1) // Both get same evaluations
        XCTAssertEqual(provider.fetchCalls.count, 1) // Only one actual fetch
    }

    func testConcurrentDifferentTargetsExecuteBoth() async {
        let target2 = Target(matchingKey: "user2")
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)
        provider.fetchDelay = 100_000_000 // 100ms

        async let fetch1: [EvaluationResult] = coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        async let fetch2: [EvaluationResult] = coordinator.fetchIfNeeded(target: target2, filters: filters, reason: .initialization)

        let result1 = await fetch1
        let result2 = await fetch2

        XCTAssertEqual(result1.count, 1)
        XCTAssertEqual(result2.count, 1)
        XCTAssertEqual(provider.fetchCalls.count, 2)
    }

    func testAfterCompletionNewIdenticalRequestExecutes() async {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)

        let result1 = await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        let result2 = await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        XCTAssertEqual(result1.count, 1)
        XCTAssertEqual(result2.count, 1)
        XCTAssertEqual(provider.fetchCalls.count, 2)
    }
}
