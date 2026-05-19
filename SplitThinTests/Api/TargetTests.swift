import XCTest
@testable import SplitThin

final class TargetTest: XCTestCase {

    func testEqualTargetsAreEqual() {
        let t1 = Target(matchingKey: "key1", bucketingKey: "bk1", attributes: ["env": "prod"], trafficType: "user")
        let t2 = Target(matchingKey: "key1", bucketingKey: "bk1", attributes: ["env": "prod"], trafficType: "user")

        XCTAssertEqual(t1, t2)
        XCTAssertEqual(t1.hashValue, t2.hashValue)
    }

    func testEqualTargetsWithMixedAttributeTypes() {
        let t1 = Target(matchingKey: "key1", attributes: ["env": "prod", "age": 30, "premium": true])
        let t2 = Target(matchingKey: "key1", attributes: ["env": "prod", "age": 30, "premium": true])

        XCTAssertEqual(t1, t2)
    }

    func testDifferentMatchingKeyNotEqual() {
        XCTAssertNotEqual(Target(matchingKey: "key1"), Target(matchingKey: "key2"))
    }

    func testDifferentBucketingKeyNotEqual() {
        XCTAssertNotEqual(
            Target(matchingKey: "key1", bucketingKey: "bk1"),
            Target(matchingKey: "key1", bucketingKey: "bk2")
        )
    }

    func testNilVsSetBucketingKeyNotEqual() {
        XCTAssertNotEqual(
            Target(matchingKey: "key1"),
            Target(matchingKey: "key1", bucketingKey: "bk1")
        )
    }

    func testDifferentAttributesNotEqual() {
        XCTAssertNotEqual(
            Target(matchingKey: "key1", attributes: ["env": "prod"]),
            Target(matchingKey: "key1", attributes: ["env": "staging"])
        )
    }

    func testNilVsEmptyAttributesNotEqual() {
        XCTAssertNotEqual(
            Target(matchingKey: "key1", attributes: nil),
            Target(matchingKey: "key1", attributes: [:])
        )
    }

    func testDifferentTrafficTypeNotEqual() {
        XCTAssertNotEqual(
            Target(matchingKey: "key1", trafficType: "user"),
            Target(matchingKey: "key1", trafficType: "account")
        )
    }

    func testHashableInSet() {
        let set: Set<Target> = [Target(matchingKey: "key1"), Target(matchingKey: "key1"), Target(matchingKey: "key2")]
        XCTAssertEqual(set.count, 2)
    }

    func testHashableAsDictionaryKey() {
        let t1 = Target(matchingKey: "key1")
        let t2 = Target(matchingKey: "key2")

        var dict = [Target: String]()
        dict[t1] = "client1"
        dict[t2] = "client2"

        XCTAssertEqual(dict[t1], "client1")
        XCTAssertEqual(dict[t2], "client2")
    }
}
