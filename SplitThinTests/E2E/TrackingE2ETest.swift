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
        try await Task.sleep(nanoseconds: 300_000_000) // Comfortably exceeds the accumulation window so the buffered write commits first

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
        try await Task.sleep(nanoseconds: 300_000_000) // Comfortably exceeds the accumulation window so the buffered write commits first

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
        try await Task.sleep(nanoseconds: 300_000_000) // Comfortably exceeds the accumulation window so the buffered write commits first

        await factory.destroy()

        XCTAssertGreaterThanOrEqual(httpMock.postEventsCalls.count, 1)
    }

    func testTrackIsNoOpAfterClientDestroyedButOthersKeepWorking() async throws {
        let client1 = factory.client // user-123
        let client2 = factory.getClient("user-B")

        let ready1 = expectation("Client 1 ready")
        let ready2 = expectation("Client 2 ready")
        client1.addEventListener(TestEventListener(readyExpectation: ready1))
        client2.addEventListener(TestEventListener(readyExpectation: ready2))
        waitFor(ready1, ready2)

        // Both clients can track before any destroy
        XCTAssertTrue(client1.track(eventType: "before", value: nil, properties: nil))
        XCTAssertTrue(client2.track(eventType: "before", value: nil, properties: nil))

        await client1.destroy()

        // A destroyed client is a no-op; the surviving client still tracks
        XCTAssertFalse(client1.track(eventType: "after", value: nil, properties: nil), "track on a destroyed client must be a no-op")
        XCTAssertTrue(client2.track(eventType: "after", value: nil, properties: nil))

        sleep(seconds: 0.3) // Exceeds the evetns accumulation window so the buffered write commits
        await client2.flush()

        let posted = httpMock.postEventsCalls.flatMap { data in
            (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        }
        XCTAssertTrue(
            posted.contains { $0["key"] as? String == "user-B" && $0["eventTypeId"] as? String == "after" },
            "Surviving client's event should be submitted"
        )
        XCTAssertFalse(
            posted.contains { $0["key"] as? String == "user-123" && $0["eventTypeId"] as? String == "after" },
            "Destroyed client's post-destroy event must never be submitted"
        )
    }

    func testTrackAfterDestroyDoesNotSubmit() async throws {
        waitUntilReady()

        await factory.destroy()
        httpMock.postEventsCalls.removeAll()

        factory.client.track(eventType: "click", value: nil, properties: nil)
        try await Task.sleep(nanoseconds: 300_000_000) // Comfortably exceeds the accumulation window so the buffered write commits first

        await factory.client.flush()

        XCTAssertEqual(httpMock.postEventsCalls.count, 0)
    }

    // MARK: - Traffic type

    func testTrackUsesTargetTrafficType() async throws {
        let customFactory = try buildFactory(httpClient: httpMock, target: Target(matchingKey: "user-123", trafficType: "account"))
        waitUntilReady(customFactory)

        customFactory.client.track(eventType: "upgrade", value: nil, properties: nil)
        try await Task.sleep(nanoseconds: 300_000_000) // Comfortably exceeds the accumulation window so the buffered write commits first

        await customFactory.client.flush()

        let payload = try JSONSerialization.jsonObject(with: httpMock.postEventsCalls[0]) as! [[String: Any]]
        XCTAssertEqual(payload[0]["trafficTypeName"] as? String, "account")

        await customFactory.destroy()
    }

    // MARK: - Event field omission

    func testTrackEventWithoutValueOmitsValueInPayload() async throws {
        waitUntilReady()

        factory.client.track(eventType: "click", value: nil, properties: nil)
        try await Task.sleep(nanoseconds: 300_000_000) // Comfortably exceeds the accumulation window so the buffered write commits first

        await factory.client.flush()

        let payload = try JSONSerialization.jsonObject(with: httpMock.postEventsCalls[0]) as! [[String: Any]]
        XCTAssertNil(payload[0]["value"])
        XCTAssertNil(payload[0]["properties"])
    }

    // MARK: - Queue threshold

    func testTrackTriggersAutoFlushWhenQueueThresholdReached() async throws {
        waitUntilReady()

        // Track past the queue-size threshold (5000). The batched writes keep Core Data
        // healthy, and crossing the threshold must auto-submit without an explicit flush().
        for _ in 0..<5100 {
            factory.client.track(eventType: "click", value: nil, properties: nil)
        }

        // Wait beyond the accumulation window so the batched write and submission complete.
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // 5100 events submitted in batches of 500 => 10 full batches + 1 of 100 = 11 posts.
        XCTAssertEqual(httpMock.postEventsCalls.count, 11, "Events should auto-submit in batches of 500 when the queue threshold is reached")
    }

    // MARK: - Helpers

    private func waitUntilReady(_ customFactory: SplitFactory? = nil) {
        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        (customFactory ?? factory).client.addEventListener(listener)
        waitFor(sdkReady)
    }
}
