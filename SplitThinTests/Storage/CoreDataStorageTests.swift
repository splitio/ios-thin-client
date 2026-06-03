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
            evaluations: [(flagName: "flag", treatment: "on", config: nil, sets: nil)]
        )
        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: "bucketing",
            evaluations: [(flagName: "flag", treatment: "off", config: nil, sets: nil)]
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
            evaluations: [(flagName: "my_flag", treatment: "on", config: nil, sets: nil)]
        )
        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: "bk",
            evaluations: [(flagName: "my_flag", treatment: "off", config: nil, sets: nil)]
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
            evaluations: [(flagName: "f1", treatment: "on", config: nil, sets: nil)]
        )
        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: "bk",
            evaluations: [(flagName: "f1", treatment: "off", config: nil, sets: nil)]
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
            evaluations: [(flagName: "flag_nil", treatment: "on", config: nil, sets: nil)]
        )
        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: "bk",
            evaluations: [(flagName: "flag_bk", treatment: "on", config: nil, sets: nil)]
        )

        let nilNames = await storage.getFlagNames(matchingKey: matchingKey, bucketingKey: nil)
        let bkNames  = await storage.getFlagNames(matchingKey: matchingKey, bucketingKey: "bk")

        XCTAssertEqual(nilNames, ["flag_nil"])
        XCTAssertEqual(bkNames,  ["flag_bk"])
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
        let persistent = PersistentStorage(storage: coreData)
        let matchingKey = "user_hash2"

        let proTarget = Target(matchingKey: matchingKey, attributes: ["plan": "pro"])
        let change = EvaluationChange(target: proTarget, changeNumber: 99, evaluations: [])
        try await persistent.upsert(change: change)

        // Same attributes — should return the stored change number
        let sameAttrTarget = Target(matchingKey: matchingKey, attributes: ["plan": "pro"])
        let changeNumberSame = await persistent.lastChangeNumber(target: sameAttrTarget)
        XCTAssertEqual(changeNumberSame, 99, "Same attributes should return stored change number")

        // Different attributes — hash mismatch should return nil
        let freeTarget = Target(matchingKey: matchingKey, attributes: ["plan": "free"])
        let changeNumberDiff = await persistent.lastChangeNumber(target: freeTarget)
        XCTAssertNil(changeNumberDiff, "Different attributes hash should cause nil change number")
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
            evaluations: [(flagName: "flag", treatment: "on", config: nil, sets: nil)]
        )
        try await storage.upsertEvaluations(
            matchingKey: matchingKey,
            bucketingKey: "bucketing",
            evaluations: [(flagName: "flag", treatment: "off", config: nil, sets: nil)]
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
