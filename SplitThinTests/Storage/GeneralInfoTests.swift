import XCTest
@testable import SplitThin

final class GeneralInfoTests: XCTestCase {

    private func makeStorage() -> CoreDataStorage {
        CoreDataStorage(databaseName: "test_\(UUID().uuidString)", inMemory: true)
    }

    // MARK: - Defaults

    func testUpdateTimestampDefaultsToZero() async {
        let storage = makeStorage()
        let value = await storage.getUpdateTimestamp()
        XCTAssertEqual(value, 0, "Unset update timestamp should default to 0")
    }

    func testRolloutCacheLastClearTimestampDefaultsToZero() async {
        let storage = makeStorage()
        let value = await storage.getRolloutCacheLastClearTimestamp()
        XCTAssertEqual(value, 0, "Unset last clear timestamp should default to 0")
    }

    // MARK: - Round trips

    func testUpdateTimestampRoundTrips() async {
        let storage = makeStorage()
        await storage.setUpdateTimestamp(1_700_000_000)

        let value = await storage.getUpdateTimestamp()
        XCTAssertEqual(value, 1_700_000_000)
    }

    func testRolloutCacheLastClearTimestampRoundTrips() async {
        let storage = makeStorage()
        await storage.setRolloutCacheLastClearTimestamp(1_699_999_999)

        let value = await storage.getRolloutCacheLastClearTimestamp()
        XCTAssertEqual(value, 1_699_999_999)
    }

    func testSetOverwritesPreviousValue() async {
        let storage = makeStorage()
        await storage.setUpdateTimestamp(1)
        await storage.setUpdateTimestamp(2)

        let value = await storage.getUpdateTimestamp()
        XCTAssertEqual(value, 2, "Setting a key twice should overwrite, not duplicate")
    }

    func testTimestampsAreIndependentKeys() async {
        let storage = makeStorage()
        await storage.setUpdateTimestamp(111)
        await storage.setRolloutCacheLastClearTimestamp(222)

        let update = await storage.getUpdateTimestamp()
        let lastClear = await storage.getRolloutCacheLastClearTimestamp()
        XCTAssertEqual(update, 111)
        XCTAssertEqual(lastClear, 222)
    }

    // MARK: - Write hook

    func testUpsertStampsUpdateTimestamp() async throws {
        let storage = makeStorage()
        let persistent = PersistentStorage(storage: storage, cacheValidator: DefaultCacheValidator(configsEnabled: false))

        let before = Int64(Date().timeIntervalSince1970)
        let target = Target(matchingKey: "user_ts", trafficType: "user")
        try await persistent.upsert(change: EvaluationChange(target: target, changeNumber: 5, evaluations: []))

        let stamped = await storage.getUpdateTimestamp()
        XCTAssertGreaterThanOrEqual(stamped, before, "upsert should stamp a fresh update timestamp")
    }

    func testConcurrentWritesLastOneWins() async {
        let storage = makeStorage()

        for iteration in 0..<100 {
            let base = Int64(iteration * 10)
            let winner = await withTaskGroup(of: Int64.self) { group in
                for offset in 0..<10 {
                    let value = base + Int64(offset)
                    group.addTask {
                        await storage.setUpdateTimestamp(value)
                        return value
                    }
                }
                var last: Int64 = 0
                for await written in group { last = written }
                return last
            }
            let value = await storage.getUpdateTimestamp()
            XCTAssertEqual(value, winner)
        }
    }
}
