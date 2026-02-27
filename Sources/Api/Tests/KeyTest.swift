import XCTest
@testable import Api

final class KeyTest: XCTestCase {
    func testKeyEquality() {
        let key1 = Key(matchingKey: "key1")
        let key2 = Key(matchingKey: "key1")

        XCTAssertEqual(key1, key2, "Instances should be equal")
        XCTAssertEqual(key1.hashValue, key2.hashValue, "Hashcodes should be equal")
        XCTAssertEqual(String(describing: key1), String(describing: key2), "toString should be equal")
    }

    func testKeyInequalityWithDifferentBucketingKey() {
        let key1 = Key(matchingKey: "key1", bucketingKey: "bkey1")
        let key2 = Key(matchingKey: "key1", bucketingKey: "bkey2")

        XCTAssertFalse(key1 == key2, "Instances should not be equal")
        XCTAssertNotEqual(key1.hashValue, key2.hashValue, "Hashcodes should not be equal")
        XCTAssertNotEqual(String(describing: key1), String(describing: key2), "toString should not be equal")
    }

    func testKeyInequalityWithDifferentMatchingKey() {
        let key1 = Key(matchingKey: "key1", bucketingKey: "bkey1")
        let key2 = Key(matchingKey: "key2", bucketingKey: "bkey1")

        XCTAssertFalse(key1 == key2, "Instances should not be equal")
        XCTAssertNotEqual(key1.hashValue, key2.hashValue, "Hashcodes should not be equal")
        XCTAssertNotEqual(String(describing: key1), String(describing: key2), "toString should not be equal")
    }

    func testKeyInequalityWithDifferentBucketingKeyAndMatchingKey() {
        let key1 = Key(matchingKey: "key1", bucketingKey: "bkey1")
        let key2 = Key(matchingKey: "key2", bucketingKey: "bkey2")

        XCTAssertFalse(key1 == key2, "Instances should not be equal")
        XCTAssertNotEqual(key1.hashValue, key2.hashValue, "Hashcodes should not be equal")
        XCTAssertNotEqual(String(describing: key1), String(describing: key2), "toString should not be equal")
    }

    func testKeyEqualityWithNilBucketingKey() {
        let key1 = Key(matchingKey: "key1")
        let key2 = Key(matchingKey: "key1", bucketingKey: nil)

        XCTAssertEqual(key1, key2, "Instances should be equal")
        XCTAssertEqual(key1.hashValue, key2.hashValue, "Hashcodes should be equal")
        XCTAssertEqual(String(describing: key1), String(describing: key2), "toString should be equal")
    }

    func testKeyInequalityWithNilBucketingKey() {
        let key1 = Key(matchingKey: "key1")
        let key2 = Key(matchingKey: "key1", bucketingKey: "bkey2")

        XCTAssertFalse(key1 == key2, "Instances should not be equal")
        XCTAssertNotEqual(key1.hashValue, key2.hashValue, "Hashcodes should not be equal")
        XCTAssertNotEqual(String(describing: key1), String(describing: key2), "toString should not be equal")
    }

    func testMatchingKeyGetter() {
        let key = Key(matchingKey: "key1")
        XCTAssertEqual(key.matchingKey, "key1", "Matching key should be equal")
    }

    func testBucketingKeyGetter() {
        let key = Key(matchingKey: "key1", bucketingKey: "bkey1")
        XCTAssertEqual(key.bucketingKey, "bkey1", "Bucketing key should be equal")
    }
}

