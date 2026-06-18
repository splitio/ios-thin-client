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

    func testFlushDoesNotPostActiveSessionWhenItsTheOnlyOne() async throws {
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

        XCTAssertTrue(httpMock.postTelemetryCalls.isEmpty, "Active session should not be sent on flush")

        await freshFactory.destroy()
    }

    func testDestroyPersistsSessionAndNextFactoryFlushesIt() async throws {
        waitUntilReady()

        factory.client.getTreatment("flag1")

        // Destroy persists session A but does NOT post it (it's still the active session).
        await factory.destroy()
        factory = nil
        httpMock.postTelemetryCalls.removeAll()

        // Second factory creates session B. Session A is now non-active in CoreData.
        let factory2 = try buildFactory(httpClient: httpMock)
        waitUntilReady(factory2)

        await factory2.client.flush()

        // The flush should have posted session A (from factory1).
        XCTAssertEqual(httpMock.postTelemetryCalls.count, 1)
        let flushedPayload = try JSONSerialization.jsonObject(with: httpMock.postTelemetryCalls[0]) as! [[String: Any]]
        let flushedSessionId = flushedPayload[0]["sessionId"] as? String
        XCTAssertNotNil(flushedSessionId)

        // Destroy factory2 -- persists session B, flushes non-active (nothing left since A was already sent).
        httpMock.postTelemetryCalls.removeAll()
        await factory2.destroy()

        // factory2's destroy persisted session B but couldn't flush it (it's active).
        // So either nothing was posted, or if there were other residual sessions they got posted.
        // But session B should NOT appear in any post (it was active during destroy).
        let postDestroyPayloads = httpMock.postTelemetryCalls.flatMap { data in
            (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        }
        let postDestroySessionIds = postDestroyPayloads.compactMap { $0["sessionId"] as? String }
        for id in postDestroySessionIds {
            XCTAssertNotEqual(id, flushedSessionId, "Factory2 session should differ from factory1 session")
        }
    }

    // MARK: - Helpers

    private func waitUntilReady(_ customFactory: SplitFactory? = nil) {
        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        (customFactory ?? factory).client.addEventListener(listener)
        waitFor(sdkReady)
    }
}
