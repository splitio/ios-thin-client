//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import XCTest
import Http
@testable import SplitThin

final class TelemetryE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!
    private var factory: SplitFactory!

    override func setUpWithError() throws {
        try super.setUpWithError()
        httpMock = SecureHttpClientMock()
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))
        factory = try buildFactory(httpClient: httpMock)
    }

    override func tearDown() async throws {
        await factory?.destroy()
        factory = nil
        httpMock = nil
        try await super.tearDown()
    }

    // MARK: - Flush

    func testFlushPostsCurrentSessionWhenItsTheOnlyOne() async throws {
        // Fresh factory with a unique prefix so no residual sessions from other tests
        let isolatedConfig = SplitClientConfig.builder()
                                              .setMinEvaluationRefreshRate(1)
                                              .set(prefix: "telemetry_\(UUID().uuidString.prefix(8))")
                                              .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpMock)
        guard let freshFactory = builder.setSdkKey("test-sdk-key")
                                        .setTarget("user-isolated")
                                        .setConfig(isolatedConfig)
                                        .build() else {
            XCTFail("Failed to build isolated factory")
            return
        }

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        freshFactory.client.addEventListener(listener)
        waitFor(sdkReady)

        freshFactory.client.getTreatment("flag1")
        httpMock.postTelemetryCalls.removeAll()

        await freshFactory.client.flush()

        XCTAssertEqual(httpMock.postTelemetryCalls.count, 1, "The current telemetry snapshot should be sent on flush")

        await freshFactory.destroy()
    }

    func testConsecutiveFlushesPostOnlyNewTelemetry() async throws {
        let isolatedConfig = SplitClientConfig.builder()
                                              .setMinEvaluationRefreshRate(1)
                                              .set(prefix: "telemetry_\(UUID().uuidString.prefix(8))")
                                              .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpMock)
        guard let freshFactory = builder.setSdkKey("test-sdk-key")
                                        .setTarget("user-isolated")
                                        .setConfig(isolatedConfig)
                                        .build() else {
            XCTFail("Failed to build isolated factory")
            return
        }

        let sdkReady = expectation("SDK ready")
        freshFactory.client.addEventListener(TestEventListener(readyExpectation: sdkReady))
        waitFor(sdkReady)

        freshFactory.client.getTreatment("flag1")
        await freshFactory.client.flush()

        httpMock.postTelemetryCalls.removeAll()
        freshFactory.client.getTreatment("flag1")
        await freshFactory.client.flush()

        let payloads = httpMock.postTelemetryCalls.flatMap { data in
            (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        }
        let runtime = payloads.first?["runtime"] as? [String: Any]

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(runtime?["evaluationCount"] as? Int, 1, "Each flush should post only telemetry recorded since the previous flush")

        await freshFactory.destroy()
    }

    func testAllClientsShareASingleTelemetrySession() async throws {
        let isolatedConfig = SplitClientConfig.builder()
                                              .setMinEvaluationRefreshRate(1)
                                              .set(prefix: "telemetry_\(UUID().uuidString.prefix(8))")
                                              .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpMock)
        guard let freshFactory = builder.setSdkKey("test-sdk-key")
                                        .setTarget("user-a")
                                        .setConfig(isolatedConfig)
                                        .build() else {
            XCTFail("Failed to build isolated factory")
            return
        }

        let sdkReady = expectation("SDK ready")
        freshFactory.client.addEventListener(TestEventListener(readyExpectation: sdkReady))
        waitFor(sdkReady)

        let secondClient = freshFactory.getClient(Target(matchingKey: "user-b", trafficType: "user"))
        freshFactory.client.getTreatment("flag1")
        secondClient.getTreatment("flag1")

        httpMock.postTelemetryCalls.removeAll()
        await freshFactory.client.flush()

        let payloads = httpMock.postTelemetryCalls.flatMap { data in
            (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        }
        let runtime = payloads.first?["runtime"] as? [String: Any]

        XCTAssertEqual(payloads.count, 1, "A factory must report a single telemetry session")
        XCTAssertEqual(runtime?["evaluationCount"] as? Int, 2, "Evaluations from every client must land in the shared session")

        await freshFactory.destroy()
    }

    func testFailedTelemetryPostDoesNotDropUnsubmittedCounters() async throws {
        let isolatedConfig = SplitClientConfig.builder()
                                              .setMinEvaluationRefreshRate(1)
                                              .set(prefix: "telemetry_\(UUID().uuidString.prefix(8))")
                                              .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpMock)
        guard let freshFactory = builder.setSdkKey("test-sdk-key")
                                        .setTarget("user-isolated")
                                        .setConfig(isolatedConfig)
                                        .build() else {
            XCTFail("Failed to build isolated factory")
            return
        }

        let sdkReady = expectation("SDK ready")
        freshFactory.client.addEventListener(TestEventListener(readyExpectation: sdkReady))
        waitFor(sdkReady)

        freshFactory.client.getTreatment("flag1")
        httpMock.postTelemetryCalls.removeAll()
        httpMock.errorToThrow = NSError(domain: "test", code: 500)
        await freshFactory.client.flush()

        httpMock.errorToThrow = nil
        httpMock.postTelemetryCalls.removeAll()
        freshFactory.client.getTreatment("flag1")
        await freshFactory.client.flush()

        let payloads = httpMock.postTelemetryCalls.flatMap { data in
            (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        }
        let runtime = payloads.first?["runtime"] as? [String: Any]

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(runtime?["evaluationCount"] as? Int, 2, "Counters persisted before a failed POST must still be submitted on the next successful flush")

        await freshFactory.destroy()
    }

    func testDestroySubmitsCompletedSession() async throws {
        // Isolated DB so residual sessions from other tests don't leak into the assertions.
        let isolatedConfig = SplitClientConfig.builder()
                                              .setMinEvaluationRefreshRate(1)
                                              .set(prefix: "telemetry_\(UUID().uuidString.prefix(8))")
                                              .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpMock)
        guard let freshFactory = builder.setSdkKey("test-sdk-key")
                                        .setTarget("user-isolated")
                                        .setConfig(isolatedConfig)
                                        .build() else {
            XCTFail("Failed to build isolated factory")
            return
        }

        let sdkReady = expectation("SDK ready")
        freshFactory.client.addEventListener(TestEventListener(readyExpectation: sdkReady))
        waitFor(sdkReady)

        freshFactory.client.getTreatment("flag1")
        httpMock.postTelemetryCalls.removeAll()

        await freshFactory.destroy()

        let payloads = httpMock.postTelemetryCalls.flatMap { data in
            (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        }
        XCTAssertEqual(payloads.count, 1, "the completed session should be submitted exactly once on destroy")
        XCTAssertNotNil(payloads.first?["sessionId"] as? String)
    }

    func testClientDestroySubmitsTelemetry() async throws {
        // Customers who never call factory.destroy() still get their telemetry on client.destroy().
        let isolatedConfig = SplitClientConfig.builder()
                                              .setMinEvaluationRefreshRate(1)
                                              .set(prefix: "telemetry_\(UUID().uuidString.prefix(8))")
                                              .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpMock)
        guard let freshFactory = builder.setSdkKey("test-sdk-key")
                                        .setTarget("user-isolated")
                                        .setConfig(isolatedConfig)
                                        .build() else {
            XCTFail("Failed to build isolated factory")
            return
        }

        let sdkReady = expectation("SDK ready")
        freshFactory.client.addEventListener(TestEventListener(readyExpectation: sdkReady))
        waitFor(sdkReady)

        freshFactory.client.getTreatment("flag1")
        httpMock.postTelemetryCalls.removeAll()

        await freshFactory.client.destroy()

        let payloads = httpMock.postTelemetryCalls.flatMap { data in
            (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        }
        XCTAssertEqual(payloads.count, 1, "client.destroy() must submit pending telemetry")
        XCTAssertEqual((payloads.first?["runtime"] as? [String: Any])?["evaluationCount"] as? Int, 1)

        await freshFactory.destroy()
    }

    func testMultiClientDestroySubmitsTheSharedSessionOnce() async throws {
        let isolatedConfig = SplitClientConfig.builder()
                                              .setMinEvaluationRefreshRate(1)
                                              .set(prefix: "telemetry_\(UUID().uuidString.prefix(8))")
                                              .build()

        let builder = DefaultSplitFactoryBuilder()
        builder.setSecureHttpClient(httpMock)
        guard let freshFactory = builder.setSdkKey("test-sdk-key")
                                        .setTarget("user-a")
                                        .setConfig(isolatedConfig)
                                        .build() else {
            XCTFail("Failed to build isolated factory")
            return
        }

        let sdkReady = expectation("SDK ready")
        freshFactory.client.addEventListener(TestEventListener(readyExpectation: sdkReady))
        waitFor(sdkReady)

        let secondClient = freshFactory.getClient(Target(matchingKey: "user-b", trafficType: "user"))
        freshFactory.client.getTreatment("flag1")
        secondClient.getTreatment("flag1")

        httpMock.postTelemetryCalls.removeAll()
        await freshFactory.destroy()

        XCTAssertEqual(httpMock.postTelemetryCalls.count, 1, "The shared session must be POSTed once, not once per client")
    }

    // MARK: - Helpers

    private func waitUntilReady(_ customFactory: SplitFactory? = nil) {
        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        (customFactory ?? factory).client.addEventListener(listener)
        waitFor(sdkReady)
    }
}
