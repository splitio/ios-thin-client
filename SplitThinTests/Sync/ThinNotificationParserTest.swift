import XCTest
@testable import SplitThin

class ThinNotificationParserTest: XCTestCase {

    var parser: ThinNotificationParser!

    override func setUp() {
        super.setUp()
        parser = DefaultThinNotificationParser()
    }

    // MARK: - parseRaw

    func testParseRawValidMessage() {
        let json = """
        {"channel":"prefix_user1","data":"{\\"type\\":\\"EVALUATION_UPDATE\\",\\"changeNumber\\":100}","timestamp":1234567890}
        """
        let raw = parser.parseRaw(jsonString: json)
        XCTAssertNotNil(raw)
        XCTAssertEqual(raw?.channel, "prefix_user1")
        XCTAssertEqual(raw?.timestamp, 1234567890)
    }

    func testParseRawInvalidJsonReturnsNil() {
        let raw = parser.parseRaw(jsonString: "not json")
        XCTAssertNil(raw)
    }

    // MARK: - parse (second phase)

    func testParseEvaluationUpdate() {
        let raw = RawThinNotification(channel: "prefix_user1",
                                      data: "{\"type\":\"EVALUATION_UPDATE\",\"changeNumber\":42}",
                                      timestamp: 1000)
        let notification = parser.parse(raw: raw)
        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.type, .evaluationUpdate)
        let update = notification as? EvaluationUpdateNotification
        XCTAssertEqual(update?.changeNumber, 42)
    }

    func testParseControl() {
        let raw = RawThinNotification(channel: "control_pri",
                                      data: "{\"type\":\"CONTROL\",\"controlType\":\"STREAMING_PAUSED\"}",
                                      timestamp: 1000)
        let notification = parser.parse(raw: raw)
        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.type, .control)
        let control = notification as? ThinControlNotification
        XCTAssertEqual(control?.controlType, .streamingPaused)
    }

    func testParseOccupancy() {
        let raw = RawThinNotification(channel: "[?occupancy=metrics.publishers]prefix_user1",
                                      data: "{\"metrics\":{\"publishers\":2}}",
                                      timestamp: 1000)
        let notification = parser.parse(raw: raw)
        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.type, .occupancy)
        let occ = notification as? ThinOccupancyNotification
        XCTAssertEqual(occ?.publishers, 2)
    }

    func testParseStreamingError() {
        let raw = RawThinNotification(channel: "control_pri",
                                      data: "{\"type\":\"ERROR\",\"message\":\"something went wrong\",\"code\":40140,\"statusCode\":401}",
                                      timestamp: 1000)
        let notification = parser.parse(raw: raw)
        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.type, .error)
        let err = notification as? ThinStreamingError
        XCTAssertEqual(err?.code, 40140)
        XCTAssertEqual(err?.statusCode, 401)
    }

    func testParseInvalidDataReturnsNil() {
        let raw = RawThinNotification(channel: "prefix_user1", data: "invalid", timestamp: 1000)
        let notification = parser.parse(raw: raw)
        XCTAssertNil(notification)
    }
}
