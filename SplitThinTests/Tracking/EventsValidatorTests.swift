//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

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

    func testEmptyTrafficTypeReturnsFalse() {
        let event = EventEntity(trafficType: "", eventType: "purchase")

        XCTAssertFalse(validator.validate(event))
    }

    func testWhitespaceOnlyReturnsFalse() {
        let event = EventEntity(trafficType: "  ", eventType: "  ")

        XCTAssertFalse(validator.validate(event))
    }
}
