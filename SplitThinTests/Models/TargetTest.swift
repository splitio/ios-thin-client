import XCTest
@testable import SplitThin

final class TargetTest: XCTestCase {

    func testEquality() {
        let t1 = Target(matchingKey: "key1", bucketingKey: "bk1", attributes: ["env": "prod"], trafficType: "user")
        let t2 = Target(matchingKey: "key1", bucketingKey: "bk1", attributes: ["env": "prod"], trafficType: "user")

        XCTAssertEqual(t1, t2)
        XCTAssertEqual(t1.hashValue, t2.hashValue)
    }

    func testEqualityMinimal() {
        let t1 = Target(matchingKey: "key1")
        let t2 = Target(matchingKey: "key1")

        XCTAssertEqual(t1, t2)
        XCTAssertEqual(t1.hashValue, t2.hashValue)
    }

    func testInequalityMatchingKey() {
        let t1 = Target(matchingKey: "key1")
        let t2 = Target(matchingKey: "key2")

        XCTAssertNotEqual(t1, t2)
        XCTAssertNotEqual(t1.hashValue, t2.hashValue)
    }

    func testInequalityBucketingKey() {
        let t1 = Target(matchingKey: "key1", bucketingKey: "bk1")
        let t2 = Target(matchingKey: "key1", bucketingKey: "bk2")

        XCTAssertNotEqual(t1, t2)
        XCTAssertNotEqual(t1.hashValue, t2.hashValue)
    }

    func testInequalityNilVsSetBucketingKey() {
        let t1 = Target(matchingKey: "key1")
        let t2 = Target(matchingKey: "key1", bucketingKey: "bk1")

        XCTAssertNotEqual(t1, t2)
        XCTAssertNotEqual(t1.hashValue, t2.hashValue)
    }

    func testInequalityAttributes() {
        let t1 = Target(matchingKey: "key1", attributes: ["env": "prod"])
        let t2 = Target(matchingKey: "key1", attributes: ["env": "staging"])

        XCTAssertNotEqual(t1, t2)
    }

    func testInequalityTrafficType() {
        let t1 = Target(matchingKey: "key1", trafficType: "user")
        let t2 = Target(matchingKey: "key1", trafficType: "account")

        XCTAssertNotEqual(t1, t2)
    }

    func testDefaultsAreNil() {
        let target = Target(matchingKey: "key1")

        XCTAssertEqual(target.matchingKey, "key1")
        XCTAssertNil(target.bucketingKey)
        XCTAssertNil(target.attributes)
        XCTAssertNil(target.trafficType)
    }

    func testAllProperties() {
        let attrs = ["env": "prod", "region": "us"]
        let target = Target(matchingKey: "key1", bucketingKey: "bk1",
                            attributes: attrs, trafficType: "user")

        XCTAssertEqual(target.matchingKey, "key1")
        XCTAssertEqual(target.bucketingKey, "bk1")
        XCTAssertEqual(target.attributes, attrs)
        XCTAssertEqual(target.trafficType, "user")
    }

    func testHashableInSet() {
        let t1 = Target(matchingKey: "key1")
        let t2 = Target(matchingKey: "key1")
        let t3 = Target(matchingKey: "key2")

        let set: Set<Target> = [t1, t2, t3]
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
