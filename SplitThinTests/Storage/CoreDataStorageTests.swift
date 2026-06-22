import XCTest
@testable import SplitThin

final class CoreDataStorageTests: XCTestCase {

    private func makeStorage() -> CoreDataStorage {
        CoreDataStorage(databaseName: "test_\(UUID().uuidString)")
    }

    // MARK: - Bucketing key isolation

    func testNilAndNonNilBucketingKeysDontOverwriteEachOther() async throws {
        let storage = makeStorage()
        let matchingKey = "user_a"

        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: nil,
            evaluations: [(flagName: "flag", treatment: "on", config: nil, sets: nil, changeNumber: nil)]
        )
        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: "bucketing",
            evaluations: [(flagName: "flag", treatment: "off", config: nil, sets: nil, changeNumber: nil)]
        )

        let nilResult = await storage.getAllEvaluations(matchingKey: matchingKey, bucketingKey: nil)
        let bucketingResult = await storage.getAllEvaluations(matchingKey: matchingKey, bucketingKey: "bucketing")

        XCTAssertEqual(nilResult.first?.treatment, "on", "nil bucketing key row should not be overwritten")
        XCTAssertEqual(bucketingResult.first?.treatment, "off", "non-nil bucketing key row should not be overwritten")
    }

    func testGetEvaluationIsolatedByBucketingKey() async throws {
        let storage = makeStorage()
        let matchingKey = "user_b"

        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: nil,
            evaluations: [(flagName: "my_flag", treatment: "on", config: nil, sets: nil, changeNumber: nil)]
        )
        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: "bk",
            evaluations: [(flagName: "my_flag", treatment: "off", config: nil, sets: nil, changeNumber: nil)]
        )

        let nilEval = await storage.getEvaluation(matchingKey: matchingKey, bucketingKey: nil, flagName: "my_flag")
        let bkEval  = await storage.getEvaluation(matchingKey: matchingKey, bucketingKey: "bk",  flagName: "my_flag")

        XCTAssertEqual(nilEval?.treatment, "on")
        XCTAssertEqual(bkEval?.treatment, "off")
    }

    func testGetEvaluationsIsolatedByBucketingKey() async throws {
        let storage = makeStorage()
        let matchingKey = "user_c"

        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: nil,
            evaluations: [(flagName: "f1", treatment: "on", config: nil, sets: nil, changeNumber: nil)]
        )
        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: "bk",
            evaluations: [(flagName: "f1", treatment: "off", config: nil, sets: nil, changeNumber: nil)]
        )

        let nilEvals = await storage.getEvaluations(matchingKey: matchingKey, bucketingKey: nil, flagNames: ["f1"])
        let bkEvals  = await storage.getEvaluations(matchingKey: matchingKey, bucketingKey: "bk",  flagNames: ["f1"])

        XCTAssertEqual(nilEvals.first?.treatment, "on")
        XCTAssertEqual(bkEvals.first?.treatment, "off")
    }

    func testGetFlagNamesIsolatedByBucketingKey() async throws {
        let storage = makeStorage()
        let matchingKey = "user_d"

        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: nil,
            evaluations: [(flagName: "flag_nil", treatment: "on", config: nil, sets: nil, changeNumber: nil)]
        )
        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: "bk",
            evaluations: [(flagName: "flag_bk", treatment: "on", config: nil, sets: nil, changeNumber: nil)]
        )

        let nilNames = await storage.getFlagNames(matchingKey: matchingKey, bucketingKey: nil)
        let bkNames  = await storage.getFlagNames(matchingKey: matchingKey, bucketingKey: "bk")

        XCTAssertEqual(nilNames, ["flag_nil"])
        XCTAssertEqual(bkNames,  ["flag_bk"])
    }

    // MARK: - Per-evaluation changeNumber

    func testEvaluationChangeNumberRoundTrips() async throws {
        let storage = makeStorage()
        let matchingKey = "user_cn"

        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: nil,
            evaluations: [
                (flagName: "with_cn", treatment: "on", config: nil, sets: nil, changeNumber: 4242),
                (flagName: "without_cn", treatment: "off", config: nil, sets: nil, changeNumber: nil)
            ]
        )

        let single = await storage.getEvaluation(matchingKey: matchingKey, bucketingKey: nil, flagName: "with_cn")
        XCTAssertEqual(single?.changeNumber, 4242, "Per-evaluation changeNumber must survive a round-trip")

        let all = await storage.getAllEvaluations(matchingKey: matchingKey, bucketingKey: nil)
        XCTAssertEqual(all.first(where: { $0.flagName == "with_cn" })?.changeNumber, 4242)
        XCTAssertNil(all.first(where: { $0.flagName == "without_cn" })?.changeNumber, "A nil changeNumber must stay nil")
    }

    // MARK: - Session isolation

    func testClientSessionIsolatedByBucketingKey() async throws {
        let storage = makeStorage()
        let matchingKey = "user_e"

        try await storage.upsertClientSession(matchingKey: matchingKey, bucketingKey: nil,         attributesHash: "", attributes: nil, changeNumber: 1)
        try await storage.upsertClientSession(matchingKey: matchingKey, bucketingKey: "bucketing", attributesHash: "", attributes: nil, changeNumber: 2)

        let nilChange = await storage.getChangeNumber(matchingKey: matchingKey, bucketingKey: nil)
        let bkChange  = await storage.getChangeNumber(matchingKey: matchingKey, bucketingKey: "bucketing")

        XCTAssertEqual(nilChange, 1)
        XCTAssertEqual(bkChange,  2)
    }

    // MARK: - Attributes hash

    func testAttributesHashStoredAndRetrieved() async throws {
        let storage = makeStorage()
        let matchingKey = "user_hash"
        let expectedHash = "my_test_hash"

        try await storage.upsertClientSession(
            matchingKey: matchingKey,
            bucketingKey: nil,
            attributesHash: expectedHash,
            attributes: nil,
            changeNumber: 1
        )

        let retrievedHash = await storage.getAttributesHash(matchingKey: matchingKey, bucketingKey: nil)
        XCTAssertEqual(retrievedHash, expectedHash)
    }

    func testAttributesHashDifferentFromStoredCausesNilChangeNumber() async throws {
        let coreData = makeStorage()
        let persistent = PersistentStorage(storage: coreData, cacheValidator: DefaultCacheValidator(configsEnabled: false))
        let matchingKey = "user_hash2"

        let proTarget = Target(matchingKey: matchingKey, attributes: ["plan": "pro"], trafficType: "user")
        let change = EvaluationChange(target: proTarget, changeNumber: 99, evaluations: [])
        try await persistent.upsert(change: change)

        // Same attributes — should return the stored change number
        let sameAttrTarget = Target(matchingKey: matchingKey, attributes: ["plan": "pro"], trafficType: "user")
        let changeNumberSame = await persistent.lastChangeNumber(target: sameAttrTarget)
        XCTAssertEqual(changeNumberSame, 99, "Same attributes should return stored change number")

        // Different attributes — hash mismatch should return nil
        let freeTarget = Target(matchingKey: matchingKey, attributes: ["plan": "free"], trafficType: "user")
        let changeNumberDiff = await persistent.lastChangeNumber(target: freeTarget)
        XCTAssertNil(changeNumberDiff, "Different attributes hash should cause nil change number")
    }

    // MARK: - configsEnabled invalidation

    func testTogglingConfigsEnabledCausesNilChangeNumber() async throws {
        let coreData = makeStorage()
        let target = Target(matchingKey: "user_configs", trafficType: "user")

        // Data persisted while configs were disabled (the default).
        let disabled = PersistentStorage(storage: coreData, cacheValidator: DefaultCacheValidator(configsEnabled: false))
        try await disabled.upsert(change: EvaluationChange(target: target, changeNumber: 99, evaluations: []))

        // Same configsEnabled — stored change number is reused.
        let stillDisabled = await disabled.lastChangeNumber(target: target)
        XCTAssertEqual(stillDisabled, 99, "Same configsEnabled should return stored change number")

        // configsEnabled flipped on — must invalidate to force a full refetch (since = -1).
        let enabled = PersistentStorage(storage: coreData, cacheValidator: DefaultCacheValidator(configsEnabled: true))
        let afterToggle = await enabled.lastChangeNumber(target: target)
        XCTAssertNil(afterToggle, "Changing configsEnabled should cause nil change number")
    }

    // MARK: - Clear scope

    func testClearDeletesByScopedIdentity() async throws {
        let storage = makeStorage()
        let matchingKey = "user_f"

        try await storage.upsertClientSession(matchingKey: matchingKey, bucketingKey: nil,         attributesHash: "", attributes: nil, changeNumber: 10)
        try await storage.upsertClientSession(matchingKey: matchingKey, bucketingKey: "bucketing", attributesHash: "", attributes: nil, changeNumber: 20)
        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: nil,
            evaluations: [(flagName: "flag", treatment: "on", config: nil, sets: nil, changeNumber: nil)]
        )
        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: "bucketing",
            evaluations: [(flagName: "flag", treatment: "off", config: nil, sets: nil, changeNumber: nil)]
        )

        // Clear only the nil-bucketing identity
        try await storage.deleteClientSession(matchingKey: matchingKey, bucketingKey: nil)

        let nilChange = await storage.getChangeNumber(matchingKey: matchingKey, bucketingKey: nil)
        let bkChange  = await storage.getChangeNumber(matchingKey: matchingKey, bucketingKey: "bucketing")
        let nilEvals  = await storage.getAllEvaluations(matchingKey: matchingKey, bucketingKey: nil)
        let bkEvals   = await storage.getAllEvaluations(matchingKey: matchingKey, bucketingKey: "bucketing")

        XCTAssertNil(nilChange, "nil-bucketing session should be deleted")
        XCTAssertEqual(bkChange, 20, "bucketing session should be untouched")
        XCTAssertTrue(nilEvals.isEmpty, "nil-bucketing evaluations should be deleted")
        XCTAssertEqual(bkEvals.first?.treatment, "off", "bucketing evaluations should be untouched")
    }
}
