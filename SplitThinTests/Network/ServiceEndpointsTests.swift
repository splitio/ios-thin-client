import XCTest
@testable import SplitThin

final class ServiceEndpointsTest: XCTestCase {

    func testDefaultEndpoints() {
        let endpoints = ServiceEndpoints.builder().build()

        XCTAssertEqual(endpoints.sdkEndpoint.absoluteString, "https://evaluator.split.io")
        XCTAssertEqual(endpoints.eventsEndpoint.absoluteString, "https://events.split.io")
        XCTAssertEqual(endpoints.authServiceEndpoint.absoluteString, "https://auth.split.io")
        XCTAssertEqual(endpoints.streamingServiceEndpoint.absoluteString, "https://streaming.split.io")
        XCTAssertEqual(endpoints.telemetryServiceEndpoint.absoluteString, "https://telemetry.split.io")
    }

    func testDefaultEndpointsAreValid() {
        let endpoints = ServiceEndpoints.builder().build()

        XCTAssertTrue(endpoints.allEndpointsValid)
        XCTAssertNil(endpoints.endpointsInvalidMessage)
    }

    func testCustomSdkEndpoint() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(sdkEndpoint: "https://custom.sdk.io")
                                        .build()

        XCTAssertEqual(endpoints.sdkEndpoint.absoluteString, "https://custom.sdk.io")
        XCTAssertTrue(endpoints.allEndpointsValid)
    }

    func testCustomEventsEndpoint() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(eventsEndpoint: "https://custom.events.io")
                                        .build()

        XCTAssertEqual(endpoints.eventsEndpoint.absoluteString, "https://custom.events.io")
        XCTAssertTrue(endpoints.allEndpointsValid)
    }

    func testCustomAuthServiceEndpoint() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(authServiceEndpoint: "https://custom.auth.io")
                                        .build()

        XCTAssertEqual(endpoints.authServiceEndpoint.absoluteString, "https://custom.auth.io")
        XCTAssertTrue(endpoints.allEndpointsValid)
    }

    func testCustomStreamingEndpoint() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(streamingServiceEndpoint: "https://custom.streaming.io")
                                        .build()

        XCTAssertEqual(endpoints.streamingServiceEndpoint.absoluteString, "https://custom.streaming.io")
        XCTAssertTrue(endpoints.allEndpointsValid)
    }

    func testCustomTelemetryEndpoint() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(telemetryServiceEndpoint: "https://custom.telemetry.io")
                                        .build()

        XCTAssertEqual(endpoints.telemetryServiceEndpoint.absoluteString, "https://custom.telemetry.io")
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

    func testInvalidSdkEndpointFallsBackToDefault() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(sdkEndpoint: "")
                                        .build()

        XCTAssertFalse(endpoints.allEndpointsValid)
        XCTAssertEqual(endpoints.sdkEndpoint.absoluteString, "https://evaluator.split.io")
    }

    func testInvalidEventsEndpointFallsBackToDefault() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(eventsEndpoint: "")
                                        .build()

        XCTAssertFalse(endpoints.allEndpointsValid)
        XCTAssertEqual(endpoints.eventsEndpoint.absoluteString, "https://events.split.io")
    }

    func testInvalidAuthEndpointFallsBackToDefault() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(authServiceEndpoint: "")
                                        .build()

        XCTAssertFalse(endpoints.allEndpointsValid)
        XCTAssertEqual(endpoints.authServiceEndpoint.absoluteString, "https://auth.split.io")
    }

    func testInvalidStreamingEndpointFallsBackToDefault() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(streamingServiceEndpoint: "")
                                        .build()

        XCTAssertFalse(endpoints.allEndpointsValid)
        XCTAssertEqual(endpoints.streamingServiceEndpoint.absoluteString, "https://streaming.split.io")
    }

    func testInvalidTelemetryEndpointFallsBackToDefault() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(telemetryServiceEndpoint: "")
                                        .build()

        XCTAssertFalse(endpoints.allEndpointsValid)
        XCTAssertEqual(endpoints.telemetryServiceEndpoint.absoluteString, "https://telemetry.split.io")
    }

    func testInvalidEndpointDoesNotAffectOtherEndpoints() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(sdkEndpoint: "")
                                        .set(eventsEndpoint: "https://custom.events.io")
                                        .build()

        XCTAssertFalse(endpoints.allEndpointsValid)
        XCTAssertEqual(endpoints.sdkEndpoint.absoluteString, "https://evaluator.split.io")
        XCTAssertEqual(endpoints.eventsEndpoint.absoluteString, "https://custom.events.io")
        XCTAssertEqual(endpoints.authServiceEndpoint.absoluteString, "https://auth.split.io")
        XCTAssertEqual(endpoints.streamingServiceEndpoint.absoluteString, "https://streaming.split.io")
        XCTAssertEqual(endpoints.telemetryServiceEndpoint.absoluteString, "https://telemetry.split.io")
    }

    func testInvalidEndpointMessageContainsOffendingValue() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(sdkEndpoint: "")
                                        .build()

        XCTAssertFalse(endpoints.allEndpointsValid)
        XCTAssertTrue(endpoints.endpointsInvalidMessage?.contains("Endpoint is invalid:") ?? false)
    }

    func testBuilderFluentApi() {
        let builder = ServiceEndpoints.builder()
                                      .set(sdkEndpoint: "https://a.io")
                                      .set(eventsEndpoint: "https://b.io")

        XCTAssertTrue(builder.build().allEndpointsValid)
    }
}
