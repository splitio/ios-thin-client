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
        coordinator = DefaultEvaluationFetchCoordinator(provider: provider, storage: EvaluationWriteStorageMock())
    }

    func testFetchReturnsEvaluations() async {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: ["set1"])]
        provider.resultToReturn = EvaluationsResult(since: -1, evaluations: evaluations, till: 100)

        let result = await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)

        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.flag, "flag1")
        XCTAssertEqual(provider.fetchCalls.count, 1)
    }

    func testFetchWithNilResultReturnsNil() async {
        provider.resultToReturn = nil

        let result = await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        XCTAssertNil(result)
        XCTAssertEqual(provider.fetchCalls.count, 1)
    }

    func testConcurrentIdenticalRequestsAreDeduplicated() async {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)
        provider.fetchDelay = 200_000_000 // 200ms

        async let fetch1: [EvaluationResult]? = coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms to ensure first fetch is in-flight
        async let fetch2: [EvaluationResult]? = coordinator.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        let result1 = await fetch1
        let result2 = await fetch2

        XCTAssertEqual(result1?.count, 1)
        XCTAssertEqual(result2?.count, 1) // Both get same evaluations
        XCTAssertEqual(provider.fetchCalls.count, 1) // Only one actual fetch
    }

    func testConcurrentDifferentTargetsExecuteBoth() async {
        let target2 = Target(matchingKey: "user2")
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)
        provider.fetchDelay = 100_000_000 // 100ms

        async let fetch1: [EvaluationResult]? = coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        async let fetch2: [EvaluationResult]? = coordinator.fetchIfNeeded(target: target2, filters: filters, reason: .initialization)

        let result1 = await fetch1
        let result2 = await fetch2

        XCTAssertEqual(result1?.count, 1)
        XCTAssertEqual(result2?.count, 1)
        XCTAssertEqual(provider.fetchCalls.count, 2)
    }

    func testAfterCompletionNewIdenticalRequestExecutes() async {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)

        let result1 = await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        let result2 = await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        XCTAssertEqual(result1?.count, 1)
        XCTAssertEqual(result2?.count, 1)
        XCTAssertEqual(provider.fetchCalls.count, 2)
    }

    func testRefetchAllWithNoFetchedKeysDoesNothing() async {
        provider.resultToReturn = EvaluationsResult(evaluations: [], till: 1)

        await coordinator.refetchAll(notification: nil)

        XCTAssertEqual(provider.fetchCalls.count, 0)
    }

    func testRefetchAllRefetchesPreviouslyFetchedKey() async {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)

        _ = await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        await coordinator.refetchAll(notification: nil)

        XCTAssertEqual(provider.fetchCalls.count, 2)
        XCTAssertEqual(provider.fetchCalls.last?.1, filters)
    }

    func testRefetchAllRefetchesMultipleDistinctKeys() async {
        let target2 = Target(matchingKey: "user2")
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)

        _ = await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        _ = await coordinator.fetchIfNeeded(target: target2, filters: filters, reason: .initialization)
        await coordinator.refetchAll(notification: nil)

        XCTAssertEqual(provider.fetchCalls.count, 4)
    }

    func testRefetchAllPassesNotificationAndKeyToDelayProvider() async {
        var delayProviderCalls: [(EvaluationUpdateNotification?, String)] = []
        let notification = EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 1,
                                                        updateIntervalMs: 5000, algorithmSeed: 42)
        coordinator = DefaultEvaluationFetchCoordinator(provider: provider, storage: EvaluationWriteStorageMock()) { notif, key in
            delayProviderCalls.append((notif, key))
            return 0
        }
        provider.resultToReturn = EvaluationsResult(evaluations: [], till: 1)

        _ = await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        await coordinator.refetchAll(notification: notification)

        XCTAssertEqual(delayProviderCalls.count, 1)
        XCTAssertEqual(delayProviderCalls.first?.0?.changeNumber, 1)
        XCTAssertEqual(delayProviderCalls.first?.1, target.matchingKey)
    }
}
