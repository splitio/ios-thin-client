import XCTest
@testable import SplitThin

class SseJwtParserTest: XCTestCase {

    var parser: SseJwtParser!

    override func setUp() {
        super.setUp()
        parser = DefaultSseJwtParser()
    }

    func testExtractChannelsFromValidJwt() {
        // JWT payload (base64url-encoded): {"x-ably-capability":"{\"channel1\":[\"subscribe\"],\"control_pri\":[\"channel-metadata:publishers\",\"subscribe\"]}","iat":1000,"exp":9999999999}
        let payload = #"{"x-ably-capability":"{\"channel1\":[\"subscribe\"],\"control_pri\":[\"channel-metadata:publishers\",\"subscribe\"]}","iat":1000,"exp":9999999999}"#
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "header.\(encoded).signature"

        let channels = parser.extractChannels(from: jwt)
        XCTAssertNotNil(channels)
        XCTAssertTrue(channels!.contains("channel1"))
        XCTAssertTrue(channels!.contains("[?occupancy=metrics.publishers]control_pri"))
    }

    func testInvalidJwtReturnsNil() {
        let channels = parser.extractChannels(from: "not.a.jwt")
        XCTAssertNil(channels)
    }

    func testMalformedPayloadReturnsNil() {
        let encoded = Data("not json".utf8).base64EncodedString()
        let jwt = "header.\(encoded).signature"
        let channels = parser.extractChannels(from: jwt)
        XCTAssertNil(channels)
    }
}
