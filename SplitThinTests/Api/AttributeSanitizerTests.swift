import XCTest
@testable import SplitThin

final class AttributeSanitizerTests: XCTestCase {

    func testNilStaysNil() {
        XCTAssertNil(AttributeSanitizer.sanitize(nil))
    }

    func testEmptyStaysEmptyNotNil() {
        let result = AttributeSanitizer.sanitize([:])
        XCTAssertNotNil(result, "an empty map must stay an empty map (distinct from nil)")
        XCTAssertEqual(result?.count, 0)
    }

    func testKeepsValidScalars() {
        let result = AttributeSanitizer.sanitize([
            "name": "pro",
            "age": 30,
            "ratio": 1.5,
            "premium": true,
        ])

        XCTAssertEqual(result?.count, 4)
        XCTAssertEqual(result?["name"] as? String, "pro")
        XCTAssertEqual(result?["age"] as? Int, 30)
        XCTAssertEqual(result?["ratio"] as? Double, 1.5)
        XCTAssertEqual(result?["premium"] as? Bool, true)
    }

    func testKeepsLists() {
        let result = AttributeSanitizer.sanitize([
            "strings": ["a", "b"],
            "numbers": [1, 2, 3],
            "bools": [true, false],
        ])

        XCTAssertEqual(result?.count, 3)
        XCTAssertEqual(result?["strings"] as? [String], ["a", "b"])
        XCTAssertEqual(result?["numbers"] as? [Int], [1, 2, 3])
        XCTAssertEqual(result?["bools"] as? [Bool], [true, false])
    }

    func testDropsInvalidEntryButKeepsTheRest() {
        let result = AttributeSanitizer.sanitize([
            "good": "value",
            "alsoGood": 42,
            "bad": Date(),          // not JSON-serializable
        ])

        XCTAssertEqual(result?.count, 2, "only the non-serializable entry must be dropped")
        XCTAssertEqual(result?["good"] as? String, "value")
        XCTAssertEqual(result?["alsoGood"] as? Int, 42)
        XCTAssertNil(result?["bad"], "a Date is not JSON-serializable and must be discarded")
    }

    func testDropsEntryWithNonSerializableInsideList() {
        let result = AttributeSanitizer.sanitize([
            "ok": "value",
            "badList": [Date(), Date()],
        ])

        XCTAssertEqual(result?.count, 1)
        XCTAssertNil(result?["badList"])
    }

    // MARK: - Wired into Target

    func testTargetSanitizesAttributesOnConstruction() {
        let target = Target(matchingKey: "user", attributes: ["plan": "pro", "joined": Date()], trafficType: "user")

        XCTAssertEqual(target.attributes?.count, 1, "Target must drop the non-serializable attribute")
        XCTAssertEqual(target.attributes?["plan"] as? String, "pro")
        XCTAssertNil(target.attributes?["joined"])
    }
}
