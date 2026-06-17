import XCTest
@testable import SplitThin

final class SplitClientEventsTest: XCTestCase {

    private var client: DefaultSplitClient!
    private var observerSpy: ObserverSpy!

    override func setUp() {
        super.setUp()
        observerSpy = ObserverSpy()
        client = buildClient(observer: observerSpy)
    }

    override func tearDown() {
        client = nil
        observerSpy = nil
        super.tearDown()
    }

    func testGetTreatmentEmitsEvaluationRequested() {
        client.getTreatment("flag_a")

        XCTAssertTrue(observerSpy.eventNames.contains("evaluationRequested"))
    }

    func testSetTargetEmitsTargetSwitchEvents() {
        client.setTarget(target: Target(matchingKey: "user2", trafficType: "user"))

        XCTAssertEqual(observerSpy.eventNames, ["targetSwitchStarted", "targetSwitchCompleted"])
    }

    func testDestroyEmitsDestroyEvents() async {
        await client.destroy()

        XCTAssertTrue(observerSpy.eventNames.contains("destroyStarted"))
        XCTAssertTrue(observerSpy.eventNames.contains("destroyCompleted"))
    }

    func testTrackEmitsTrackCalled() {
        client.track(eventType: "purchase", value: nil, properties: nil)

        XCTAssertTrue(observerSpy.eventNames.contains("trackCalled"))
    }

    func testTrackAfterDestroyEmitsTrackDropped() async {
        await client.destroy()

        client.track(eventType: "purchase", value: nil, properties: nil)

        XCTAssertTrue(observerSpy.eventNames.contains("trackDropped"))
    }

    func testFlushEmitsFlushEvents() async {
        await client.flush()

        XCTAssertTrue(observerSpy.notifiedEvents.contains { if case .flushStarted(.telemetry) = $0 { return true }; return false })
        XCTAssertTrue(observerSpy.notifiedEvents.contains { if case .flushCompleted(.telemetry) = $0 { return true }; return false })
    }
}
