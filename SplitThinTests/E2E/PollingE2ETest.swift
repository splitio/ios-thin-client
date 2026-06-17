import XCTest
import Http
@testable import SplitThin

final class PollingE2ETest: XCTestCase {

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

    // MARK: - Tests

    func testPollingFetchesPeriodically() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate1 = expectation("SDK update 1")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate1)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"], treatment: "off", till: 12346))

        waitFor(sdkUpdate1)

        factory.client.removeEventListener(listener)

        let sdkUpdate2 = expectation("SDK update 2")
        let listener2 = TestEventListener(updateExpectation: sdkUpdate2)
        factory.client.addEventListener(listener2)

        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"], treatment: "on", till: 12347))

        waitFor(sdkUpdate2)

        let callCount = httpMock.fetchEvaluationsCalls.count
        XCTAssertGreaterThanOrEqual(callCount, 3, "Expected at least 3 fetches, got \(callCount)")
    }

    func testPollingUpdatesClientTreatments() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let result = factory.client.getTreatment("my-flag")
        XCTAssertEqual(result.treatment, "on")
    }

    func testPollingStopsOnDestroy() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)
        await factory.destroy()

        let callCountAfterDestroy = httpMock.fetchEvaluationsCalls.count

        sleep(seconds: 1.5) // Give time to verify no more fetches

        let callCountLater = httpMock.fetchEvaluationsCalls.count
        XCTAssertEqual(callCountAfterDestroy, callCountLater, "No more fetches should occur after destroy")
    }

    func testSingleSyncOnlyFetchesOnce() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation("SDK ready")
        let noUpdate = expectation("SDK update").inverted()
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: noUpdate)
        factory = try buildFactory(httpClient: httpMock) // default: singleSync
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        let callCount = httpMock.fetchEvaluationsCalls.count
        XCTAssertEqual(callCount, 1, "SingleSync should fetch exactly once, got \(callCount)")
        XCTAssertEqual(factory.client.getTreatment("my-flag").treatment, "on")

        // Change the backend response. SINGLE_SYNC has no background refresh, so this must never
        // be picked up: no extra fetch, no SDK_UPDATE, and the treatment stays put.
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"], treatment: "off", till: 12346))

        waitFor(noUpdate, timeout: 1.5)

        XCTAssertEqual(listener.onUpdateCallCount, 0, "SINGLE_SYNC must not emit SDK_UPDATE")
        XCTAssertEqual(httpMock.fetchEvaluationsCalls.count, 1, "SINGLE_SYNC must not fetch again")
        XCTAssertEqual(factory.client.getTreatment("my-flag").treatment, "on", "Treatment must stay unchanged in SINGLE_SYNC")
    }

    func testDestroyingLastClientStopsPolling() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        // Destroy via client.destroy() (not factory.destroy()): the last client owns the
        // only sync manager, so its polling scheduler must stop.
        await factory.client.destroy()
        let callCountAfterDestroy = httpMock.fetchEvaluationsCalls.count

        sleep(seconds: 2.5) // Spans 2+ poll cycles if polling were still alive

        XCTAssertEqual(callCountAfterDestroy, httpMock.fetchEvaluationsCalls.count, "Polling must stop after the last client is destroyed via client.destroy()")
    }

    func testDestroyingOneClientKeepsOthersPolling() async throws {
        httpMock.fetchEvaluationsResultByKey["user-A"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"])))
        httpMock.fetchEvaluationsResultByKey["user-B"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_b"])))

        let readyA = expectation("Client A ready")
        let readyB = expectation("Client B ready")
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1, target: Target(matchingKey: "user-A", trafficType: "user"))
        let clientB = factory.getClient("user-B")
        factory.client.addEventListener(TestEventListener(readyExpectation: readyA))
        clientB.addEventListener(TestEventListener(readyExpectation: readyB))

        waitFor(readyA, readyB)

        // Destroy only client A. Each client owns its own polling scheduler, so A must stop
        // while B keeps polling on the shared (but per-target) infrastructure.
        await factory.client.destroy()
        let aCallsAtDestroy = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "user-A" }.count
        let bCallsAtDestroy = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "user-B" }.count

        sleep(seconds: 2.5) // Spans 2+ poll cycles

        let aCallsAfter = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "user-A" }.count
        let bCallsAfter = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "user-B" }.count

        XCTAssertEqual(aCallsAfter, aCallsAtDestroy, "Destroyed client A must stop polling")
        XCTAssertGreaterThan(bCallsAfter, bCallsAtDestroy, "Surviving client B must keep polling")
    }

    // setTarget must move the polling loop onto the new key: the old key stops being polled
    // and the new one starts getting periodic refreshes.
    func testSetTargetSwitchesPolledTarget() async throws {
        httpMock.fetchEvaluationsResultByKey["user-A"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"])))
        httpMock.fetchEvaluationsResultByKey["user-B"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_b"])))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1, target: Target(matchingKey: "user-A", trafficType: "user"))
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        factory.client.setTarget(target: Target(matchingKey: "user-B", trafficType: "user"))

        sleep(seconds: 0.5) // Let any in-flight user-A cycle finish and the switch take hold

        let aCallsAtSwitch = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "user-A" }.count
        let bCallsAtSwitch = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "user-B" }.count

        sleep(seconds: 2.5) // Spans 2+ poll cycles

        let aCallsAfter = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "user-A" }.count
        let bCallsAfter = httpMock.fetchEvaluationsCalls.filter { $0.target.matchingKey == "user-B" }.count

        XCTAssertEqual(aCallsAfter, aCallsAtSwitch, "Polling must stop fetching the old target after setTarget")
        XCTAssertGreaterThan(bCallsAfter, bCallsAtSwitch, "Polling must keep fetching the new target after setTarget")
    }

    // MARK: - SDK_UPDATE via Polling

    func testSdkReadyFiresOnlyOnce() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        sleep(3)

        XCTAssertEqual(listener.onReadyCallCount, 1)
    }

    func testSdkUpdateMetadataContainsFlagNames() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["feature_a", "feature_b"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["feature_a", "feature_b"], treatment: "off", till: 12346))

        waitFor(sdkUpdate)

        XCTAssertNotNil(listener.lastUpdateMetadata)
        XCTAssertEqual(listener.lastUpdateMetadata?.type, .flagsUpdate)

        let names = listener.lastUpdateMetadata?.names ?? []
        XCTAssertTrue(names.contains("feature_a"))
        XCTAssertTrue(names.contains("feature_b"))
    }

    func testFirstUpdateDoesNotFireBeforeReady() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertEqual(listener.onUpdateCallCount, 0)

        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"], treatment: "off", till: 12346))

        waitFor(sdkUpdate) // First polling cycle
    }

    func testPollingUpdatesRepository() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"], treatment: "v1"))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        XCTAssertEqual(factory.client.getTreatment("my-flag").treatment, "v1")

        // Change the response before the next polling cycle
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["my-flag"], treatment: "v2"))

        waitFor(sdkUpdate)

        XCTAssertEqual(factory.client.getTreatment("my-flag").treatment, "v2")
    }

    // MARK: - Multi-Client Polling Updates

    func testMulticlientUpdatesAreIsolated() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let ready1 = expectation("Client 1 ready")
        let ready2 = expectation("Client 2 ready")
        let update1 = expectation("Client 1 update")
        let update2 = expectation("Client 2 update")
        let listener1 = TestEventListener(readyExpectation: ready1, updateExpectation: update1)
        let listener2 = TestEventListener(readyExpectation: ready2, updateExpectation: update2)

        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1, target: Target(matchingKey: "user-A", trafficType: "user"))
        let client2 = factory.getClient("user-B")

        factory.client.addEventListener(listener1)
        client2.addEventListener(listener2)

        waitFor(ready1, ready2)

        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"], treatment: "off", till: 12346))

        waitFor(update1, update2)
    }

    // MARK: - Diff: only changed flags in metadata

    func testUpdateMetadataOnlyContainsNewlyAddedFlags() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a", "flag_b", "flag_c"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a", "flag_b", "flag_c", "flag_d", "flag_e"], till: 12346))

        waitFor(sdkUpdate)

        let names = Set(listener.lastUpdateMetadata?.names ?? [])
        XCTAssertEqual(names, ["flag_d", "flag_e"], "Only the 2 newly added flags should appear in metadata")
    }

    func testUpdateMetadataOnlyContainsRemovedFlag() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a", "flag_b", "flag_c"]))

        let sdkReady = expectation("SDK ready")
        let sdkUpdate = expectation("SDK update")
        let listener = TestEventListener(readyExpectation: sdkReady, updateExpectation: sdkUpdate)
        factory = try buildFactory(httpClient: httpMock, syncMode: .polling, refreshRate: 1)
        factory.client.addEventListener(listener)

        waitFor(sdkReady)

        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a", "flag_b"], till: 12346))

        waitFor(sdkUpdate)

        let names = Set(listener.lastUpdateMetadata?.names ?? [])
        XCTAssertEqual(names, ["flag_c"], "Only the removed flag should appear in metadata")
    }
}
