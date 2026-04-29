//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import XCTest
import Http
@testable import SplitThin

final class TrackingE2ETest: XCTestCase {

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

    // MARK: - Track + Flush

    func testTrackAndFlushSubmitsEventToBackend() async throws {
        waitUntilReady()

        factory.client.track(eventType: "purchase", value: 42.0, properties: ["plan": "pro"])
        try await Task.sleep(nanoseconds: 100_000_000)

        await factory.client.flush()

        XCTAssertEqual(httpMock.postEventsCalls.count, 1)
        let payload = try JSONSerialization.jsonObject(with: httpMock.postEventsCalls[0]) as! [[String: Any]]
        XCTAssertEqual(payload.count, 1)
        XCTAssertEqual(payload[0]["eventTypeId"] as? String, "purchase")
        XCTAssertEqual(payload[0]["trafficTypeName"] as? String, "user")
        XCTAssertEqual(payload[0]["value"] as? Double, 42.0)
        XCTAssertEqual(payload[0]["properties"] as? [String: String], ["plan": "pro"])
    }

    func testMultipleTracksAreBatchedOnFlush() async throws {
        waitUntilReady()

        factory.client.track(eventType: "click", value: nil, properties: nil)
        factory.client.track(eventType: "purchase", value: 10.0, properties: nil)
        factory.client.track(eventType: "login", value: nil, properties: nil)
        try await Task.sleep(nanoseconds: 100_000_000)

        await factory.client.flush()

        XCTAssertEqual(httpMock.postEventsCalls.count, 1)
        let payload = try JSONSerialization.jsonObject(with: httpMock.postEventsCalls[0]) as! [[String: Any]]
        XCTAssertEqual(payload.count, 3)
    }

    func testFlushWithNoEventsDoesNotPost() async throws {
        waitUntilReady()

        await factory.client.flush()

        XCTAssertEqual(httpMock.postEventsCalls.count, 0)
    }

    // MARK: - Destroy

    func testDestroyFlushesRemainingEvents() async throws {
        waitUntilReady()

        factory.client.track(eventType: "purchase", value: nil, properties: nil)
        try await Task.sleep(nanoseconds: 100_000_000)

        await factory.destroy()

        XCTAssertGreaterThanOrEqual(httpMock.postEventsCalls.count, 1)
    }

    func testTrackAfterDestroyDoesNotSubmit() async throws {
        waitUntilReady()

        await factory.destroy()
        httpMock.postEventsCalls.removeAll()

        factory.client.track(eventType: "click", value: nil, properties: nil)
        try await Task.sleep(nanoseconds: 100_000_000)

        await factory.client.flush()

        XCTAssertEqual(httpMock.postEventsCalls.count, 0)
    }

    // MARK: - Event field omission

    func testTrackEventWithoutValueOmitsValueInPayload() async throws {
        waitUntilReady()

        factory.client.track(eventType: "click", value: nil, properties: nil)
        try await Task.sleep(nanoseconds: 100_000_000)

        await factory.client.flush()

        let payload = try JSONSerialization.jsonObject(with: httpMock.postEventsCalls[0]) as! [[String: Any]]
        XCTAssertNil(payload[0]["value"])
        XCTAssertNil(payload[0]["properties"])
    }

    // MARK: - Helpers

    private func waitUntilReady() {
        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory.client.addEventListener(listener)
        waitFor(sdkReady)
    }
}
