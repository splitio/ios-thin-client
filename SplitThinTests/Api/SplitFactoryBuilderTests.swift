import XCTest
import Http
@testable import SplitThin

final class DefaultSplitFactoryBuilderTest: XCTestCase {

    func testBuildWithNoParams() {
        let factory = DefaultSplitFactoryBuilder().build()

        XCTAssertNil(factory, "Factory should be nil when no params are set")
    }

    func testBuildWithEmptySdkKey() {
        let factory = DefaultSplitFactoryBuilder().setSdkKey(SdkKey(""))
                                                  .setTarget(Target(matchingKey: "user1"))
                                                  .build()

        XCTAssertNil(factory, "Factory should be nil with empty SDK key")
    }

    func testBuildWithNoTarget() {
        let factory = DefaultSplitFactoryBuilder().setSdkKey(SdkKey("api-key-123"))
                                                  .build()

        XCTAssertNil(factory, "Factory should be nil when target is missing")
    }

    func testBuildWithEmptyMatchingKey() {
        let factory = DefaultSplitFactoryBuilder().setSdkKey(SdkKey("api-key-123"))
                                                  .setTarget(Target(matchingKey: ""))
                                                  .build()

        XCTAssertNil(factory, "Factory should be nil with empty matching key")
    }

    func testBuildSuccess() {
        let factory = DefaultSplitFactoryBuilder().setSdkKey(SdkKey("api-key-123"))
                                                  .setTarget(Target(matchingKey: "user1"))
                                                  .build()

        XCTAssertNotNil(factory, "Factory should not be nil with valid params")
    }

    func testBuildSuccessWithAllParams() {
        let config = SplitClientConfig.builder()
                                      .set(evaluationRefreshRate: 120)
                                      .set(syncMode: .polling)
                                      .build()

        let filters = EvaluationFilters(flagNames: ["flag_a"], flagSets: ["set_1"])
        let target = Target(matchingKey: "user1", bucketingKey: "bk1",
                            attributes: ["env": "prod"], trafficType: "user")

        let factory = DefaultSplitFactoryBuilder().setSdkKey(SdkKey("api-key-123"))
                                                  .setTarget(target)
                                                  .setConfig(config)
                                                  .setEvaluationFilters(filters)
                                                  .build()

        XCTAssertNotNil(factory, "Factory should not be nil with all params")
    }

    func testBuildWithInvalidEndpointsReturnsNil() {
        let config = SplitClientConfig.builder()
                                      .set(serviceEndpoints: ServiceEndpoints.builder()
                                                                             .set(sdkEndpoint: "not a valid url ://")
                                                                             .build())
                                      .build()

        let factory = DefaultSplitFactoryBuilder().setSdkKey(SdkKey("api-key-123"))
                                                  .setTarget(Target(matchingKey: "user1"))
                                                  .setConfig(config)
                                                  .build()

        XCTAssertNil(factory, "Factory should be nil with invalid endpoints")
    }

    func testSetStreamingConnectionManagerFactoryIsUsed() async throws {
        let connectionManagerMock = StreamingConnectionManagerMock()
        let httpMock = SecureHttpClientMock()
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: []))

        let sdkReady = expectation(description: "SDK ready")
        let listener = TestEventListener(onReadyExpectation: sdkReady)

        let config = SplitClientConfig.builder()
                                      .setMinEvaluationRefreshRate(1)
                                      .set(syncMode: .streaming)
                                      .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpMock)
        builder.setStreamingConnectionManagerFactory { _ in connectionManagerMock }

        guard let factory = builder.setSdkKey(SdkKey("api-key-123"))
                                   .setTarget(Target(matchingKey: "user1"))
                                   .setConfig(config)
                                   .build() else {
            XCTFail("Factory should build"); return
        }
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        XCTAssertEqual(connectionManagerMock.startCallCount, 1,
                       "Injected connection manager factory should be used when streaming starts")
        await factory.destroy()
    }

    func testFluentApiReturnsSelf() {
        let builder = DefaultSplitFactoryBuilder()

        let b1 = builder.setSdkKey(SdkKey("key"))
        let b2 = b1.setTarget(Target(matchingKey: "user1"))
        let b3 = b2.setConfig(SplitClientConfig.builder().build())
        let b4 = b3.setEvaluationFilters(EvaluationFilters())

        XCTAssertNotNil(b4.build())
    }
}
