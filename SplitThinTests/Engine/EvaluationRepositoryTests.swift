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

    // MARK: - applyFetched guard

    func testApplyFetchedAppliesWhenShouldApplyToCache() {
        let result = FetchResult(
            evaluations: [EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])],
            changeNumber: 1,
            shouldApplyToCache: true
        )

        let changed = repository.applyFetched(result, for: target)

        XCTAssertEqual(changed, ["flag1"])
        XCTAssertEqual(repository.getEvaluation(flag: "flag1", target: target)?.evaluationResult.treatment, "on")
    }

    func testApplyFetchedDoesNotWipeCacheWhenShouldNotApply() {
        // Seed the cache (e.g. hydrated from persistence)
        repository.update([EvaluationResult(flag: "flag1", treatment: "on", flagSets: [])], for: target)

        // An up-to-date / empty response must not be applied
        let upToDate = FetchResult(evaluations: [], changeNumber: 500, shouldApplyToCache: false)
        let changed = repository.applyFetched(upToDate, for: target)

        XCTAssertTrue(changed.isEmpty, "Skipped apply reports no changed flags")
        XCTAssertEqual(repository.getEvaluation(flag: "flag1", target: target)?.evaluationResult.treatment, "on", "Existing cache must survive an up-to-date response")
    }

    // MARK: - loadFromCache (network-wins guard)

    func testCacheLoadDoesNotOverwriteNetworkResult() {
        // Network lands first with data.
        let fresh = FetchResult(evaluations: [EvaluationResult(flag: "flag1", treatment: "fresh", flagSets: [])], changeNumber: 10, shouldApplyToCache: true)
        repository.applyFetched(fresh, for: target)

        // A slow disk read lands afterwards; it must NOT overwrite what the network wrote.
        let changed = repository.loadFromCache([EvaluationResult(flag: "flag1", treatment: "stale", flagSets: [])], for: target)

        XCTAssertTrue(changed.isEmpty, "A cache load after the network wrote must be a no-op")
        XCTAssertEqual(repository.getEvaluation(flag: "flag1", target: target)?.evaluationResult.treatment, "fresh", "The network result must not be overwritten by a later cache load")
    }

    func testCacheLoadAppliesWhenNetworkHasNotWritten() {
        // Network hasn't touched this target yet → the cache load populates memory.
        let changed = repository.loadFromCache([EvaluationResult(flag: "flag1", treatment: "disk", flagSets: [])], for: target)

        XCTAssertEqual(changed, ["flag1"])
        XCTAssertEqual(repository.getEvaluation(flag: "flag1", target: target)?.evaluationResult.treatment, "disk", "Cache load must apply when the network hasn't written yet")
    }

    func testUpToDateResultDoesNotBlockCacheLoad() {
        // An up-to-date (empty) response carries no data and is skipped (shouldApplyToCache == false),
        // leaving the target untouched (`nil`) — so the cache load still hydrates memory.
        let upToDate = FetchResult(evaluations: [], changeNumber: 10, shouldApplyToCache: false)
        repository.applyFetched(upToDate, for: target)

        let changed = repository.loadFromCache([EvaluationResult(flag: "flag1", treatment: "disk", flagSets: [])], for: target)

        XCTAssertEqual(changed, ["flag1"])
        XCTAssertEqual(repository.getEvaluation(flag: "flag1", target: target)?.evaluationResult.treatment, "disk", "An up-to-date response must not block the cache load")
    }

    func testCacheLoadDoesNotResurrectFlagsRemovedByNetwork() {
        // Network removes all flags (empty, but with new data so it's applied → entry becomes `[:]`).
        let cleared = FetchResult(evaluations: [], changeNumber: 10, shouldApplyToCache: true)
        repository.applyFetched(cleared, for: target)

        // A slow disk read carrying the old flags must NOT bring them back.
        let changed = repository.loadFromCache([EvaluationResult(flag: "flag1", treatment: "stale", flagSets: [])], for: target)

        XCTAssertTrue(changed.isEmpty, "A cache load must not resurrect flags the server removed")
        XCTAssertNil(repository.getEvaluation(flag: "flag1", target: target), "Flags removed by the network must stay removed")
    }

    // MARK: - setTarget hydration

    func testSetTargetHydratesFromPersistedStorage() async {
        let readStorage = EvaluationStorageMock()
        readStorage.evaluationsToReturn = [EvaluationResult(flag: "persisted", treatment: "v1", flagSets: [])]
        let coordinator = EvaluationFetchCoordinatorMock()
        // Up-to-date fetch (empty + should not apply) so only the hydration populates the cache
        coordinator.evaluationsToReturn = []
        coordinator.shouldApplyToCacheToReturn = false
        let repo = DefaultEvaluationRepository(fetchCoordinator: coordinator, evaluationFilters: nil, readStorage: readStorage)

        repo.setTarget(target)

        waitUntil(timeout: 2) {
            repo.getEvaluation(flag: "persisted", target: self.target)?.evaluationResult.treatment == "v1"
        }

        XCTAssertEqual(readStorage.getAllCallCount, 1, "setTarget must hydrate the new target from persisted storage")
        XCTAssertEqual(repo.getEvaluation(flag: "persisted", target: target)?.evaluationResult.treatment, "v1", "Persisted cache for the new target must be available after setTarget")
    }

    // MARK: - setTarget refetch decision

    func testTrafficTypeDoesNotRefetch() {
        let coordinator = EvaluationFetchCoordinatorMock()
        let repo = DefaultEvaluationRepository(fetchCoordinator: coordinator, evaluationFilters: nil)

        repo.setTarget(Target(matchingKey: "user1", trafficType: "user"))
        waitUntil(timeout: 2) { coordinator.fetchCalls.count == 1 }

        // Only the trafficType changes 
        repo.setTarget(Target(matchingKey: "user1", trafficType: "account"))
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(coordinator.fetchCalls.count, 1, "A trafficType-only change must not trigger a refetch")
    }

    func testBucketingChangeRefetches() {
        let coordinator = EvaluationFetchCoordinatorMock()
        let repo = DefaultEvaluationRepository(fetchCoordinator: coordinator, evaluationFilters: nil)

        repo.setTarget(Target(matchingKey: "user1", trafficType: "user"))
        waitUntil(timeout: 2) { coordinator.fetchCalls.count == 1 }

        // The bucketingKey changes → refetch.
        repo.setTarget(Target(matchingKey: "user1", bucketingKey: "bucket-2", trafficType: "user"))
        waitUntil(timeout: 2) { coordinator.fetchCalls.count == 2 }
    }
}
