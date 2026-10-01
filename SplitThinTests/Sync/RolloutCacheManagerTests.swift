import XCTest
@testable import SplitThin

final class RolloutCacheManagerTests: XCTestCase {

    private var storage: CoreDataStorage!
    private var evaluationRepository: EvaluationRepositoryMock!
    private var persistent: PersistentStorage!

    override func setUp() {
        super.setUp()
        storage = CoreDataStorage(databaseName: "test_rollout_\(UUID().uuidString)", inMemory: true)
        evaluationRepository = EvaluationRepositoryMock()
        persistent = PersistentStorage(storage: storage, cacheValidator: DefaultCacheValidator(configsEnabled: false))
    }

    // MARK: - Spec: Expiration period is used

    func testExpirationClearsPersistedEvaluations() async throws {
        try await seedEvaluations(matchingKey: "user_a", changeNumber: 42)
        await storage.setUpdateTimestamp(timestamp(daysAgo: 11))

        let manager = makeManager(expirationDays: 10)
        await manager.validateCache()

        let remaining = await storage.getAllEvaluations(matchingKey: "user_a", bucketingKey: nil)
        XCTAssertEqual(remaining.isEmpty, true)
        XCTAssertEqual(evaluationRepository.clearCalledTimes, 1)
        let lastClear = await storage.getRolloutCacheLastClearTimestamp()
        XCTAssertGreaterThan(lastClear, 0)
    }

    // MARK: - Spec: Clear on init clears cache on startup

    func testClearOnInitClearsPersistedEvaluations() async throws {
        try await seedEvaluations(matchingKey: "user_b", changeNumber: 7)
        await storage.setUpdateTimestamp(timestamp(daysAgo: 0))

        let manager = makeManager(expirationDays: 10, clearOnInit: true)
        await manager.validateCache()

        let remaining = await storage.getAllEvaluations(matchingKey: "user_b", bucketingKey: nil)
        XCTAssertEqual(remaining.isEmpty, true)
        XCTAssertEqual(evaluationRepository.clearCalledTimes, 1)
    }

    // MARK: - Spec: Clear on init does not clear if cleared less than 1 day ago

    func testClearOnInitSkipsWhenClearedRecently() async throws {
        try await seedEvaluations(matchingKey: "user_c", changeNumber: 9)
        await storage.setUpdateTimestamp(timestamp(daysAgo: 0))
        await storage.setRolloutCacheLastClearTimestamp(timestamp(daysAgo: 0))

        let manager = makeManager(expirationDays: 10, clearOnInit: true)
        await manager.validateCache()

        let remaining = await storage.getAllEvaluations(matchingKey: "user_c", bucketingKey: nil)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(evaluationRepository.clearCalledTimes, 0)
    }

    // MARK: - Thin-client delta: no clear preserves cache

    func testNoExpirationAndFreshTimestampPreservesCache() async throws {
        try await seedEvaluations(matchingKey: "user_d", changeNumber: 3)
        await storage.setUpdateTimestamp(timestamp(daysAgo: 1))

        let manager = makeManager(expirationDays: 10, clearOnInit: false)
        await manager.validateCache()

        let remaining = await storage.getAllEvaluations(matchingKey: "user_d", bucketingKey: nil)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.treatment, "on")
        XCTAssertEqual(evaluationRepository.clearCalledTimes, 0)
        let lastClear = await storage.getRolloutCacheLastClearTimestamp()
        XCTAssertEqual(lastClear, 0)
    }

    // MARK: - Edge cases (parity with ios-client unit tests)

    func testDefaultUpdateTimestampDoesNotClear() async {
        let manager = makeManager(expirationDays: 10)
        await manager.validateCache()
        XCTAssertEqual(evaluationRepository.clearCalledTimes, 0)
    }

    func testDefaultLastClearTimestampClearsWhenClearOnInit() async throws {
        try await seedEvaluations(matchingKey: "user_e", changeNumber: 1)

        let manager = makeManager(expirationDays: 10, clearOnInit: true)
        await manager.validateCache()

        let remaining = await storage.getAllEvaluations(matchingKey: "user_e", bucketingKey: nil)
        XCTAssertEqual(remaining.isEmpty, true)
        XCTAssertEqual(evaluationRepository.clearCalledTimes, 1)
    }

    func testClearOnInitOnlyClearsOnceWhenValidatedConsecutively() async throws {
        try await seedEvaluations(matchingKey: "user_f", changeNumber: 1)
        await storage.setUpdateTimestamp(timestamp(daysAgo: 1))

        let manager = makeManager(expirationDays: 10, clearOnInit: true)
        await manager.validateCache()
        await manager.validateCache()

        XCTAssertEqual(evaluationRepository.clearCalledTimes, 1)
    }

    func testClearWipesAllSessionsGlobally() async throws {
        try await seedEvaluations(matchingKey: "user_1", changeNumber: 1)
        try await seedEvaluations(matchingKey: "user_2", changeNumber: 2)
        await storage.setUpdateTimestamp(timestamp(daysAgo: 20))

        let manager = makeManager(expirationDays: 10)
        await manager.validateCache()

        let a = await storage.getAllEvaluations(matchingKey: "user_1", bucketingKey: nil)
        let b = await storage.getAllEvaluations(matchingKey: "user_2", bucketingKey: nil)
        XCTAssertEqual(a.isEmpty, true)
        XCTAssertEqual(b.isEmpty, true)
    }

    func testClearAlsoWipesClientSession() async throws {
        try await seedEvaluations(matchingKey: "user_session", changeNumber: 99)
        let sessionBefore = await storage.getChangeNumber(matchingKey: "user_session", bucketingKey: nil)
        XCTAssertEqual(sessionBefore, 99)

        await storage.setUpdateTimestamp(timestamp(daysAgo: 11))
        await makeManager(expirationDays: 10).validateCache()

        let sessionChangeNumber = await storage.getChangeNumber(matchingKey: "user_session", bucketingKey: nil)
        XCTAssertNil(sessionChangeNumber, "ClientSession must be wiped along with evaluations")
    }

    // MARK: - Helpers

    private func makeManager(expirationDays: Int, clearOnInit: Bool = false) -> DefaultRolloutCacheManager {
        DefaultRolloutCacheManager(
            storage: storage,
            configuration: RolloutCacheConfiguration.builder()
                .set(expirationDays: expirationDays)
                .set(clearOnInit: clearOnInit)
                .build(),
            evaluationRepository: evaluationRepository
        )
    }

    private func seedEvaluations(matchingKey: String, changeNumber: Int64) async throws {
        let target = Target(matchingKey: matchingKey, trafficType: "user")
        let evaluations = [EvaluationResult(flag: "flag_a", treatment: "on", changeNumber: changeNumber, flagSets: [], config: nil)]
        try await persistent.upsert(change: EvaluationChange(target: target, changeNumber: changeNumber, evaluations: evaluations))
    }

    private func timestamp(daysAgo: Int) -> Int64 {
        Int64(Date().timeIntervalSince1970) - Int64(daysAgo * 86_400)
    }
}
