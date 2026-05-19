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
        {"channel":"prefix_user1","data":"{\\"type\\":\\"EVALUATIONS_UPDATE\\",\\"changeNumber\\":100}","timestamp":1234567890}
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
        let raw = makeRaw(
            channel: "prefix_user1",
            innerData: "{\"type\":\"EVALUATIONS_UPDATE\",\"changeNumber\":42}",
            timestamp: 1000)
        let notification = parser.parse(raw: raw)
        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.type, .evaluationUpdate)
        XCTAssertEqual(notification?.channel, "prefix_user1")
        XCTAssertEqual(notification?.timestamp, 1000)
        let update = notification as? EvaluationUpdateNotification
        XCTAssertEqual(update?.changeNumber, 42)
    }

    func testParseEvaluationUpdateWithAllFields() {
        let payload = "{\"type\":\"EVALUATIONS_UPDATE\",\"changeNumber\":1776901840728,\"dt\":0,\"u\":0,\"s\":0,\"h\":1,\"i\":60000}"
        let raw = makeRaw(channel: "prefix_user1", innerData: payload, timestamp: 1000)
        let update = parser.parse(raw: raw) as? EvaluationUpdateNotification
        XCTAssertNotNil(update)
        XCTAssertEqual(update?.changeNumber, 1776901840728)
        XCTAssertEqual(update?.dataType, .flagUpdate)
        XCTAssertEqual(update?.updateStrategy, .fetchAll)
        XCTAssertEqual(update?.algorithmSeed, 0)
        XCTAssertEqual(update?.hashingAlgorithm, 1)
        XCTAssertEqual(update?.updateIntervalMs, 60000)
    }

    func testParseControl() {
        let raw = makeRaw(
            channel: "control_pri",
            innerData: "{\"type\":\"CONTROL\",\"controlType\":\"STREAMING_PAUSED\"}",
            timestamp: 1000)
        let notification = parser.parse(raw: raw)
        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.type, .control)
        let control = notification as? ThinControlNotification
        XCTAssertEqual(control?.controlType, .streamingPaused)
    }

    func testParseOccupancy() {
        let raw = makeRaw(
            channel: "[?occupancy=metrics.publishers]prefix_user1",
            innerData: "{\"metrics\":{\"publishers\":2}}",
            timestamp: 1000)
        let notification = parser.parse(raw: raw)
        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.type, .occupancy)
        let occ = notification as? ThinOccupancyNotification
        XCTAssertEqual(occ?.publishers, 2)
    }

    func testParseStreamingError() {
        let raw = makeRaw(
            channel: "control_pri",
            innerData: "{\"type\":\"ERROR\",\"message\":\"something went wrong\",\"code\":40140,\"statusCode\":401}",
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

    func testParseMissingInnerDataReturnsNil() {
        let raw = RawThinNotification(channel: "prefix_user1", data: "{\"channel\":\"ch\"}", timestamp: 1000)
        let notification = parser.parse(raw: raw)
        XCTAssertNil(notification)
    }

    // MARK: - Helpers

    /// Builds a RawThinNotification whose `data` is the SSE envelope JSON containing channel, timestamp,
    /// and a nested "data" field with the escaped inner payload.
    private func makeRaw(channel: String, innerData: String, timestamp: Int64) -> RawThinNotification {
        let escaped = innerData.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: "\"", with: "\\\"")
        let envelope = "{\"channel\":\"\(channel)\",\"data\":\"\(escaped)\",\"timestamp\":\(timestamp)}"
        return RawThinNotification(channel: "", data: envelope, timestamp: 0)
    }
}
