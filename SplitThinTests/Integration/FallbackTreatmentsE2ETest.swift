import XCTest
import Http
@testable import SplitThin

final class FallbackTreatmentsE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!
    private var factory: SplitFactory!

    override func setUp() {
        super.setUp()
        httpMock = SecureHttpClientMock()
    }

    override func tearDown() async throws {
        await factory?.destroy()
        factory = nil
        httpMock = nil
        try await super.tearDown()
    }

    // MARK: - Global Fallbacks

    func testGlobalFallbackBeforeSdkReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))
        let fallbacks = FallbackTreatmentsConfig.builder().global("fallback_treatment").build()

        factory = try buildFactory(httpClient: httpMock, fallbackTreatments: fallbacks)

        let result = factory.client.getTreatment(flag: "my-flag")

        XCTAssertEqual(result.treatment, "fallback_treatment")
    }

    func testGlobalFallbackReturnsServerValueAfterSdkReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))
        let fallbacks = FallbackTreatmentsConfig.builder().global("fallback_treatment").build()

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, fallbackTreatments: fallbacks)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let result = factory.client.getTreatment(flag: "my-flag")

        XCTAssertEqual(result.treatment, "on")
    }

    func testGlobalFallbackForNonExistentFlagAfterSdkReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["existing-flag"]))
        let fallbacks = FallbackTreatmentsConfig.builder().global("fallback_treatment").build()

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, fallbackTreatments: fallbacks)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let result = factory.client.getTreatment(flag: "non-existent-flag")

        XCTAssertEqual(result.treatment, "fallback_treatment")
    }

    func testGlobalFallbackWithConfig() async throws {
        let fallbacks = FallbackTreatmentsConfig.builder()
                                                .global(FallbackTreatment(treatment: "fallback_v2", config: "{\"version\":2}"))
                                                .build()

        factory = try buildFactory(httpClient: httpMock, fallbackTreatments: fallbacks)

        let result = factory.client.getTreatment(flag: "any-flag")

        XCTAssertEqual(result.treatment, "fallback_v2")
        XCTAssertEqual(result.config, "{\"version\":2}")
    }

    // MARK: - By Flag Fallbacks

    func testByFlagFallbackBeforeSdkReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))
        let fallbacks = FallbackTreatmentsConfig.builder().byFlag(["my-flag": "flag_fallback"]).build()

        factory = try buildFactory(httpClient: httpMock, fallbackTreatments: fallbacks)

        let result = factory.client.getTreatment(flag: "my-flag")

        XCTAssertEqual(result.treatment, "flag_fallback")
    }

    func testByFlagFallbackReturnsServerValueAfterSdkReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))
        let fallbacks = FallbackTreatmentsConfig.builder().byFlag(["my-flag": "flag_fallback"]).build()

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, fallbackTreatments: fallbacks)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let result = factory.client.getTreatment(flag: "my-flag")

        XCTAssertEqual(result.treatment, "on")
    }

    func testByFlagFallbackForNonExistentFlagAfterSdkReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["existing-flag"]))
        let fallbacks = FallbackTreatmentsConfig.builder().byFlag(["non-existent-flag": "flag_fallback"]).build()

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, fallbackTreatments: fallbacks)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let result = factory.client.getTreatment(flag: "non-existent-flag")

        XCTAssertEqual(result.treatment, "flag_fallback")
    }

    func testByFlagFallbackWithConfig() async throws {
        let fallbacks = FallbackTreatmentsConfig.builder()
                                                .byFlag(["checkout": FallbackTreatment(treatment: "premium", config: "{\"features\":[\"a\",\"b\"]}")])
                                                .build()

        factory = try buildFactory(httpClient: httpMock, fallbackTreatments: fallbacks)

        let result = factory.client.getTreatment(flag: "checkout")

        XCTAssertEqual(result.treatment, "premium")
        XCTAssertEqual(result.config, "{\"features\":[\"a\",\"b\"]}")
    }

    // MARK: - Priority: byFlag > global > control

    func testByFlagOverridesGlobal() async throws {
        let fallbacks = FallbackTreatmentsConfig.builder()
                                                .global("global_fallback")
                                                .byFlag(["specific-flag": "flag_fallback"])
                                                .build()

        factory = try buildFactory(httpClient: httpMock, fallbackTreatments: fallbacks)

        let specificResult = factory.client.getTreatment(flag: "specific-flag")
        let otherResult = factory.client.getTreatment(flag: "other-flag")

        XCTAssertEqual(specificResult.treatment, "flag_fallback")
        XCTAssertEqual(otherResult.treatment, "global_fallback")
    }

    func testNoFallbackReturnsControl() async throws {
        factory = try buildFactory(httpClient: httpMock)

        let result = factory.client.getTreatment(flag: "any-flag")

        XCTAssertEqual(result.treatment, "control")
    }
}
