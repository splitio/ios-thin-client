import XCTest
@testable import SplitThin

final class EventEntityTest: XCTestCase {

    func testAllProperties() {
        let ts = Date(timeIntervalSince1970: 1700000000)
        let props = ["plan": "premium"]
        let event = EventEntity(trafficType: "user",
                                eventType: "purchase",
                                value: 9.99,
                                properties: props,
                                timestamp: ts)

        XCTAssertEqual(event.trafficType, "user")
        XCTAssertEqual(event.eventType, "purchase")
        XCTAssertEqual(event.value ?? 0, 9.99, accuracy: 0.001)
        XCTAssertEqual(event.properties, props)
        XCTAssertEqual(event.timestamp, ts)
    }

    func testDefaults() {
        let before = Date()
        let event = EventEntity(trafficType: "user", eventType: "login")
        let after = Date()

        XCTAssertEqual(event.trafficType, "user")
        XCTAssertEqual(event.eventType, "login")
        XCTAssertNil(event.value)
        XCTAssertNil(event.properties)
        XCTAssertTrue(event.timestamp >= before && event.timestamp <= after)
    }
}
