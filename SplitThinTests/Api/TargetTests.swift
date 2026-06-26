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
        let t1 = Target(matchingKey: "key1", attributes: ["env": "prod", "age": 30, "premium": true], trafficType: "user")
        let t2 = Target(matchingKey: "key1", attributes: ["env": "prod", "age": 30, "premium": true], trafficType: "user")

        XCTAssertEqual(t1, t2)
    }

    func testAttributeOrderDoesNotAffectEquality() {
        let t1 = Target(matchingKey: "key1", attributes: ["env": "prod", "age": 30, "premium": true], trafficType: "user")
        let t2 = Target(matchingKey: "key1", attributes: ["premium": true, "env": "prod", "age": 30], trafficType: "user")

        XCTAssertEqual(t1, t2, "Attribute declaration order must not affect Target equality")
        XCTAssertEqual(t1.hashValue, t2.hashValue)
    }

    func testDifferentMatchingKeyNotEqual() {
        XCTAssertNotEqual(Target(matchingKey: "key1", trafficType: "user"), Target(matchingKey: "key2", trafficType: "user"))
    }

    func testDifferentBucketingKeyNotEqual() {
        XCTAssertNotEqual(
            Target(matchingKey: "key1", bucketingKey: "bk1", trafficType: "user"),
            Target(matchingKey: "key1", bucketingKey: "bk2", trafficType: "user")
        )
    }

    func testNilVsSetBucketingKeyNotEqual() {
        XCTAssertNotEqual(
            Target(matchingKey: "key1", trafficType: "user"),
            Target(matchingKey: "key1", bucketingKey: "bk1", trafficType: "user")
        )
    }

    func testDifferentAttributesNotEqual() {
        XCTAssertNotEqual(
            Target(matchingKey: "key1", attributes: ["env": "prod"], trafficType: "user"),
            Target(matchingKey: "key1", attributes: ["env": "staging"], trafficType: "user")
        )
    }

    func testNilVsEmptyAttributesNotEqual() {
        XCTAssertNotEqual(
            Target(matchingKey: "key1", attributes: nil, trafficType: "user"),
            Target(matchingKey: "key1", attributes: [:], trafficType: "user")
        )
    }

    func testDifferentTrafficTypeNotEqual() {
        XCTAssertNotEqual(
            Target(matchingKey: "key1", trafficType: "user"),
            Target(matchingKey: "key1", trafficType: "account")
        )
    }

    func testHashableInSet() {
        let set: Set<Target> = [Target(matchingKey: "key1", trafficType: "user"), Target(matchingKey: "key1", trafficType: "user"), Target(matchingKey: "key2", trafficType: "user")]
        XCTAssertEqual(set.count, 2)
    }

    func testHashableAsDictionaryKey() {
        let t1 = Target(matchingKey: "key1", trafficType: "user")
        let t2 = Target(matchingKey: "key2", trafficType: "user")

        var dict = [Target: String]()
        dict[t1] = "client1"
        dict[t2] = "client2"

        XCTAssertEqual(dict[t1], "client1")
        XCTAssertEqual(dict[t2], "client2")
    }
}
