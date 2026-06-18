import XCTest
@testable import SplitThin

final class DefaultEvaluationFetchCoordinatorTest: XCTestCase {

    private var provider: EvaluationProviderMock!
    private var coordinator: DefaultEvaluationFetchCoordinator!

    private let target = Target(matchingKey: "user1", trafficType: "user")
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
        let target2 = Target(matchingKey: "user2", trafficType: "user")
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

        await coordinator.refetchAll(delay: .none)

        XCTAssertEqual(provider.fetchCalls.count, 0)
    }

    func testRefetchAllRefetchesPreviouslyFetchedKey() async throws {
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)

        _ = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        await coordinator.refetchAll(delay: .none)

        XCTAssertEqual(provider.fetchCalls.count, 2)
        XCTAssertEqual(provider.fetchCalls.last?.1, filters)
    }

    func testRefetchAllRefetchesMultipleDistinctKeys() async throws {
        let target2 = Target(matchingKey: "user2", trafficType: "user")
        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(evaluations: evaluations, till: 1)

        _ = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        _ = try await coordinator.fetchIfNeeded(target: target2, filters: filters, reason: .initialization)
        await coordinator.refetchAll(delay: .none)

        XCTAssertEqual(provider.fetchCalls.count, 4)
    }

    // MARK: - refetchKeys

    func testRefetchKeysOnlyFetchesMatchingKeys() async throws {
        let target2 = Target(matchingKey: "user2", trafficType: "user")
        provider.resultToReturn = EvaluationsResult(evaluations: [], till: 1)

        _ = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        _ = try await coordinator.fetchIfNeeded(target: target2, filters: filters, reason: .initialization)
        await coordinator.refetchKeys(["user1"], delay: .none)

        // 2 initial + 1 refetch (only user1)
        XCTAssertEqual(provider.fetchCalls.count, 3)
        XCTAssertEqual(provider.fetchCalls.last?.0.matchingKey, "user1")
    }

    func testRefetchKeysWithEmptySetDoesNothing() async throws {
        provider.resultToReturn = EvaluationsResult(evaluations: [], till: 1)

        _ = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        await coordinator.refetchKeys([], delay: .none)

        XCTAssertEqual(provider.fetchCalls.count, 1)
    }

    // MARK: - Since / Till

    func testFetchSkipsStorageWhenTillMatchesStoredChangeNumber() async throws {
        let readStorage = EvaluationStorageMock()
        readStorage.changeNumberToReturn = 500
        let writeStorage = EvaluationWriteStorageMock()
        let coord = DefaultEvaluationFetchCoordinator(provider: provider, observer: ObserverSpy(), storage: writeStorage, readStorage: readStorage)

        // Server returns till == stored changeNumber and empty evaluations (nothing changed)
        provider.resultToReturn = EvaluationsResult(since: 500, evaluations: [], till: 500)

        _ = try await coord.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        XCTAssertEqual(writeStorage.upsertCalls.count, 0, "Storage should NOT be written when till == stored changeNumber")
    }

    func testFetchPersistsWhenTillDoesNotMatchesStoredChangeNumberAndEvaluationsIsEmpty() async throws {
        let readStorage = EvaluationStorageMock()
        readStorage.changeNumberToReturn = 500
        let writeStorage = EvaluationWriteStorageMock()
        let coord = DefaultEvaluationFetchCoordinator(provider: provider, observer: ObserverSpy(), storage: writeStorage, readStorage: readStorage)

        // Server returns till == stored changeNumber and empty evaluations (nothing changed)
        provider.resultToReturn = EvaluationsResult(since: 499, evaluations: [], till: 510)

        _ = try await coord.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        XCTAssertEqual(writeStorage.upsertCalls.count, 1, "Storage should be written when evaluations is empty")
    }

    func testPushWithEmptyFlagsAndSinceTillMinusOneStillNotifiesUpdate() async throws {
        provider.resultToReturn = EvaluationsResult(since: -1, evaluations: [], till: -1)

        let updateNotified = expectation("onUpdateAction invoked")
        coordinator.registerOnUpdateAction(for: target.key) { _ in updateNotified.fulfill() }

        _ = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .push)

        waitFor(updateNotified)
    }

    func testFetchPersistsWhenTillDiffersFromStoredChangeNumber() async throws {
        let readStorage = EvaluationStorageMock()
        readStorage.changeNumberToReturn = 500
        let writeStorage = EvaluationWriteStorageMock()
        let coord = DefaultEvaluationFetchCoordinator(provider: provider, observer: ObserverSpy(), storage: writeStorage, readStorage: readStorage)

        let evaluations = [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])]
        provider.resultToReturn = EvaluationsResult(since: 500, evaluations: evaluations, till: 501)

        _ = try await coord.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        // Storage write is dispatched in a Task; give it a moment
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(writeStorage.upsertCalls.count, 1, "Storage should be written when till != stored changeNumber")
        XCTAssertEqual(writeStorage.upsertCalls.first?.changeNumber, 501)
    }

    // MARK: - shouldApplyToCache

    func testShouldApplyToCacheTrueWhenServerHasNewData() async throws {
        let readStorage = EvaluationStorageMock()
        readStorage.changeNumberToReturn = 500
        let coord = DefaultEvaluationFetchCoordinator(provider: provider, observer: ObserverSpy(), readStorage: readStorage)

        provider.resultToReturn = EvaluationsResult(since: 500, evaluations: [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])], till: 510)

        let result = try await coord.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        XCTAssertTrue(result.shouldApplyToCache, "Fresh data (till > stored) must be applied to the in-memory cache")
    }

    func testShouldApplyToCacheTrueWhenEmptyAccount() async throws {
        let readStorage = EvaluationStorageMock()
        readStorage.changeNumberToReturn = -1
        let coord = DefaultEvaluationFetchCoordinator(provider: provider, observer: ObserverSpy(), readStorage: readStorage)

        provider.resultToReturn = EvaluationsResult(since: -1, evaluations: [], till: -1)

        let result = try await coord.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        XCTAssertTrue(result.shouldApplyToCache, "An empty account (since/till == -1) must be applied so the cache reflects no flags")
    }

    func testShouldApplyToCacheFalseWhenUpToDate() async throws {
        let readStorage = EvaluationStorageMock()
        readStorage.changeNumberToReturn = 500
        let coord = DefaultEvaluationFetchCoordinator(provider: provider, observer: ObserverSpy(), readStorage: readStorage)

        // Server confirms up to date: till == stored changeNumber, empty evaluations.
        provider.resultToReturn = EvaluationsResult(since: 500, evaluations: [], till: 500)

        let result = try await coord.fetchIfNeeded(target: target, filters: filters, reason: .periodic)

        XCTAssertFalse(result.shouldApplyToCache, "An up-to-date empty response must NOT wipe the in-memory cache")
    }

    // MARK: - Unregister

    func testUnregisterRemovesTargetFromRefetchAll() async throws {
        provider.resultToReturn = EvaluationsResult(evaluations: [], till: 1)

        _ = try await coordinator.fetchIfNeeded(target: target, filters: filters, reason: .initialization)
        coordinator.unregister(target: target)
        await coordinator.refetchAll(delay: .none)

        // Only the initial fetch, no refetch after unregister
        XCTAssertEqual(provider.fetchCalls.count, 1)
    }
}
