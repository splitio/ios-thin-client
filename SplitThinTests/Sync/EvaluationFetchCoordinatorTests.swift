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
        coordinator = DefaultEvaluationFetchCoordinator(provider: provider, observer: ObserverSpy())
    }

    func testFetchReturnsEvaluations() async throws {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: ["set1"])]
        provider.resultToReturn = EvaluationsResult(since: -1, evaluations: evaluations, till: 100)

        let result = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)

        XCTAssertEqual(result.evaluations.count, 1)
        XCTAssertEqual(result.evaluations.first?.flag, "flag1")
        XCTAssertEqual(result.changeNumber, 100)
        XCTAssertEqual(provider.fetchCalls.count, 1)
    }

    func testFetchWithNilResultThrows() async {
        provider.resultToReturn = nil

        do {
            _ = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .periodic)
            XCTFail("Expected fetchFailed error")
        } catch {
            XCTAssertTrue(error is EvaluationFetchError)
        }
        XCTAssertEqual(provider.fetchCalls.count, 1)
    }

    func testConcurrentIdenticalRequestsAreDeduplicated() async throws {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)
        provider.fetchDelay = 200_000_000 // 200ms

        async let fetch1: FetchResult = coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms to ensure first fetch is in-flight
        async let fetch2: FetchResult = coordinator.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        let result1 = try await fetch1
        let result2 = try await fetch2

        XCTAssertEqual(result1.evaluations.count, 1)
        XCTAssertEqual(result2.evaluations.count, 1)
        XCTAssertEqual(provider.fetchCalls.count, 1)
    }

    func testConcurrentDifferentTargetsExecuteBoth() async throws {
        let target2 = Target(matchingKey: "user2")
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)
        provider.fetchDelay = 100_000_000 // 100ms

        async let fetch1: FetchResult = coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        async let fetch2: FetchResult = coordinator.fetchIfNeeded(target: target2, filters: filters, reason: .initialization)

        let result1 = try await fetch1
        let result2 = try await fetch2

        XCTAssertEqual(result1.evaluations.count, 1)
        XCTAssertEqual(result2.evaluations.count, 1)
        XCTAssertEqual(provider.fetchCalls.count, 2)
    }

    func testAfterCompletionNewIdenticalRequestExecutes() async throws {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)

        let result1 = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        let result2 = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        XCTAssertEqual(result1.evaluations.count, 1)
        XCTAssertEqual(result2.evaluations.count, 1)
        XCTAssertEqual(provider.fetchCalls.count, 2)
    }

    func testRefetchAllWithNoFetchedKeysDoesNothing() async {
        provider.resultToReturn = EvaluationsResult(evaluations: [], till: 1)

        await coordinator.refetchAll(notification: nil)

        XCTAssertEqual(provider.fetchCalls.count, 0)
    }

    func testRefetchAllRefetchesPreviouslyFetchedKey() async throws {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)

        _ = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        await coordinator.refetchAll(notification: nil)

        XCTAssertEqual(provider.fetchCalls.count, 2)
        XCTAssertEqual(provider.fetchCalls.last?.1, filters)
    }

    func testRefetchAllRefetchesMultipleDistinctKeys() async throws {
        let target2 = Target(matchingKey: "user2")
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)

        _ = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        _ = try await coordinator.fetchIfNeeded(target: target2, filters: filters, reason: .initialization)
        await coordinator.refetchAll(notification: nil)

        XCTAssertEqual(provider.fetchCalls.count, 4)
    }

    func testRefetchAllPassesNotificationAndKeyToDelayProvider() async throws {
        var delayProviderCalls: [(EvaluationUpdateNotification?, String)] = []
        let notification = EvaluationUpdateNotification(channel: nil, timestamp: 0, changeNumber: 1,
                                                        algorithmSeed: 42, updateIntervalMs: 5000)
        coordinator = DefaultEvaluationFetchCoordinator(provider: provider, observer: ObserverSpy()) { notif, key in
            delayProviderCalls.append((notif, key))
            return 0
        }
        provider.resultToReturn = EvaluationsResult(evaluations: [], till: 1)

        _ = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        await coordinator.refetchAll(notification: notification)

        XCTAssertEqual(delayProviderCalls.count, 1)
        XCTAssertEqual(delayProviderCalls.first?.0?.changeNumber, 1)
        XCTAssertEqual(delayProviderCalls.first?.1, target.matchingKey)
    }
}
