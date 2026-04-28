import XCTest
@testable import SplitThin

final class DefaultEventsValidatorTest: XCTestCase {

    private var validator: DefaultEventsValidator!

    override func setUp() {
        super.setUp()
        validator = DefaultEventsValidator()
    }

    func testValidEventReturnsTrue() {
        let event = EventEntity(trafficType: "user", eventType: "purchase")

        XCTAssertTrue(validator.validate(event))
    }

    func testEmptyEventTypeReturnsFalse() {
        let event = EventEntity(trafficType: "user", eventType: "")

        XCTAssertFalse(validator.validate(event))
    }

    func testWhitespaceEventTypeReturnsFalse() {
        let event = EventEntity(trafficType: "user", eventType: "   ")

        XCTAssertFalse(validator.validate(event))
    }

    func testEmptyTrafficTypeReturnsFalse() {
        let event = EventEntity(trafficType: "", eventType: "purchase")

        XCTAssertFalse(validator.validate(event))
    }

    func testWhitespaceTrafficTypeReturnsFalse() {
        let event = EventEntity(trafficType: "  ", eventType: "purchase")

        XCTAssertFalse(validator.validate(event))
    }

}
