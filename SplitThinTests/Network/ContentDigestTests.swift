import XCTest
@testable import SplitThin

final class ContentDigestTest: XCTestCase {

    // MARK: - Hash input serialization

    func testWithAttributes() {
        let target = Target(matchingKey: "Mauro", attributes: ["city": "mdp", "age": 150])

        let input = ContentDigest.buildHashInput(for: target)

        XCTAssertEqual(input, "Mauro::{\"age\":150,\"city\":\"mdp\"}")
    }

    func testSortsAttributeKeys() {
        let target = Target(matchingKey: "user1", attributes: ["zebra": "z", "alpha": "a", "middle": "m"])

        let input = ContentDigest.buildHashInput(for: target)

        XCTAssertEqual(input, "user1::{\"alpha\":\"a\",\"middle\":\"m\",\"zebra\":\"z\"}")
    }

    func testWithBucketingKey() {
        let target = Target(matchingKey: "user1", bucketingKey: "bucket1", attributes: ["flag": true])

        let input = ContentDigest.buildHashInput(for: target)

        XCTAssertEqual(input, "user1:bucket1:{\"flag\":true}")
    }

    func testWithNilAttributes() {
        let target = Target(matchingKey: "user1")

        let input = ContentDigest.buildHashInput(for: target)

        XCTAssertEqual(input, "user1::{}")
    }

    func testWithEmptyAttributes() {
        let target = Target(matchingKey: "user1", attributes: [:])

        let input = ContentDigest.buildHashInput(for: target)

        XCTAssertEqual(input, "user1::{}")
    }

    func testOmitsNullAttributes() {
        let target = Target(matchingKey: "user1", attributes: ["keep": "yes", "drop": NSNull()])

        let input = ContentDigest.buildHashInput(for: target)

        XCTAssertEqual(input, "user1::{\"keep\":\"yes\"}")
    }

    func testCollectionSorted() {
        let target = Target(matchingKey: "user1", attributes: ["tags": ["beta", "alpha", "gamma"]])

        let input = ContentDigest.buildHashInput(for: target)

        XCTAssertEqual(input, "user1::{\"tags\":[\"alpha\",\"beta\",\"gamma\"]}")
    }

    func testCollectionOmitsNulls() {
        let target = Target(matchingKey: "user1", attributes: ["items": ["b", NSNull(), "a"] as [Any]])

        let input = ContentDigest.buildHashInput(for: target)

        XCTAssertEqual(input, "user1::{\"items\":[\"a\",\"b\"]}")
    }

    func testWithMixedTypes() {
        let target = Target(matchingKey: "user1", attributes: ["name": "Alice", "age": 30, "active": true])

        let input = ContentDigest.buildHashInput(for: target)

        XCTAssertEqual(input, "user1::{\"active\":true,\"age\":30,\"name\":\"Alice\"}")
    }

    // MARK: - Full digest computation

    func testMatchesExpectedValue() {
        let target = Target(matchingKey: "Mauro", attributes: ["city": "mdp", "age": 150])

        let digest = ContentDigest.compute(for: target)

        XCTAssertEqual(digest, "EVu1Yxs6Jvs")
    }

    func testWithNoAttributes() {
        let target = Target(matchingKey: "user1")

        let digest = ContentDigest.compute(for: target)

        XCTAssertEqual(digest, "2YsSrtAzlcI")
    }

    func testIsDeterministic() {
        let target = Target(matchingKey: "Mauro", attributes: ["city": "mdp", "age": 150])

        let digest1 = ContentDigest.compute(for: target)
        let digest2 = ContentDigest.compute(for: target)

        XCTAssertEqual(digest1, digest2)
    }
}
