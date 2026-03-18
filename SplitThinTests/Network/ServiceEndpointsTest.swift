import XCTest
@testable import SplitThin

final class ServiceEndpointsTest: XCTestCase {

    func testDefaultEndpoints() {
        let endpoints = ServiceEndpoints.builder().build()

        XCTAssertEqual(endpoints.sdkEndpoint.absoluteString, "https://sdk.split.io/api")
        XCTAssertEqual(endpoints.eventsEndpoint.absoluteString, "https://events.split.io/api")
        XCTAssertEqual(endpoints.authServiceEndpoint.absoluteString, "https://auth.split.io/api/v3")
        XCTAssertEqual(endpoints.streamingServiceEndpoint.absoluteString, "https://streaming.split.io/sse")
        XCTAssertEqual(endpoints.telemetryServiceEndpoint.absoluteString, "https://telemetry.split.io/api/v1")
    }

    func testDefaultEndpointsAreValid() {
        let endpoints = ServiceEndpoints.builder().build()

        XCTAssertTrue(endpoints.allEndpointsValid)
        XCTAssertNil(endpoints.endpointsInvalidMessage)
    }

    func testCustomSdkEndpoint() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(sdkEndpoint: "https://custom.sdk.io/api")
                                        .build()

        XCTAssertEqual(endpoints.sdkEndpoint.absoluteString, "https://custom.sdk.io/api")
        XCTAssertTrue(endpoints.allEndpointsValid)
    }

    func testCustomEventsEndpoint() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(eventsEndpoint: "https://custom.events.io/api")
                                        .build()

        XCTAssertEqual(endpoints.eventsEndpoint.absoluteString, "https://custom.events.io/api")
        XCTAssertTrue(endpoints.allEndpointsValid)
    }

    func testCustomAuthServiceEndpoint() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(authServiceEndpoint: "https://custom.auth.io/api")
                                        .build()

        XCTAssertEqual(endpoints.authServiceEndpoint.absoluteString, "https://custom.auth.io/api")
        XCTAssertTrue(endpoints.allEndpointsValid)
    }

    func testCustomStreamingEndpoint() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(streamingServiceEndpoint: "https://custom.streaming.io/sse")
                                        .build()

        XCTAssertEqual(endpoints.streamingServiceEndpoint.absoluteString, "https://custom.streaming.io/sse")
        XCTAssertTrue(endpoints.allEndpointsValid)
    }

    func testCustomTelemetryEndpoint() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(telemetryServiceEndpoint: "https://custom.telemetry.io/api")
                                        .build()

        XCTAssertEqual(endpoints.telemetryServiceEndpoint.absoluteString, "https://custom.telemetry.io/api")
        XCTAssertTrue(endpoints.allEndpointsValid)
    }

    func testAllCustomEndpoints() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(sdkEndpoint: "https://a.io")
                                        .set(eventsEndpoint: "https://b.io")
                                        .set(authServiceEndpoint: "https://c.io")
                                        .set(streamingServiceEndpoint: "https://d.io")
                                        .set(telemetryServiceEndpoint: "https://e.io")
                                        .build()

        XCTAssertEqual(endpoints.sdkEndpoint.absoluteString, "https://a.io")
        XCTAssertEqual(endpoints.eventsEndpoint.absoluteString, "https://b.io")
        XCTAssertEqual(endpoints.authServiceEndpoint.absoluteString, "https://c.io")
        XCTAssertEqual(endpoints.streamingServiceEndpoint.absoluteString, "https://d.io")
        XCTAssertEqual(endpoints.telemetryServiceEndpoint.absoluteString, "https://e.io")
        XCTAssertTrue(endpoints.allEndpointsValid)
    }

    func testInvalidEndpointMarksAsInvalid() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(sdkEndpoint: "")
                                        .build()

        XCTAssertFalse(endpoints.allEndpointsValid)
        XCTAssertNotNil(endpoints.endpointsInvalidMessage)
    }

    func testBuilderFluentApi() {
        let builder = ServiceEndpoints.builder()
                                      .set(sdkEndpoint: "https://a.io")
                                      .set(eventsEndpoint: "https://b.io")

        XCTAssertTrue(builder.build().allEndpointsValid)
    }
}
