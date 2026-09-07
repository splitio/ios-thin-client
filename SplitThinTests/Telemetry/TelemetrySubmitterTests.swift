import XCTest
import Http
@testable import SplitThin

final class TelemetrySubmitterTests: XCTestCase {

    private var storage: TelemetryStorageMock!
    private var httpClient: SecureHttpClientMock!
    private var observerStorage: TelemetryStorageMock!
    private var observer: TelemetryObserver!
    private var sut: DefaultTelemetrySubmitter!

    override func setUp() {
        super.setUp()
        storage = TelemetryStorageMock()
        httpClient = SecureHttpClientMock()
        observerStorage = TelemetryStorageMock()
        observer = TelemetryObserver(storage: observerStorage, sessionId: "s1", config: SplitClientConfig.builder().build())
        sut = DefaultTelemetrySubmitter(storage: storage, secureHttpClient: httpClient, observer: observer)
    }

    // MARK: - Successful flush

    func testFlushPostsAllSessionsAndRemovesThem() async {
        let record1 = makeRecord(sessionId: "s1")
        let record2 = makeRecord(sessionId: "s2")
        storage.allRecords = [record1, record2]

        await sut.flush(count: nil)

        XCTAssertEqual(httpClient.postTelemetryCalls.count, 1)
        XCTAssertEqual(storage.removedSessionIds.count, 1)
        XCTAssertEqual(storage.removedSessionIds.first, ["s1", "s2"])
    }

    func testFlushWithCountLimitsSessionsSent() async {
        storage.allRecords = [makeRecord(sessionId: "s1"), makeRecord(sessionId: "s2"), makeRecord(sessionId: "s3")]

        await sut.flush(count: 2)

        XCTAssertEqual(storage.removedSessionIds.first, ["s1", "s2"])
    }

    // MARK: - Empty storage

    func testFlushWithEmptyStorageIsNoOp() async {
        storage.allRecords = []

        await sut.flush(count: nil)

        XCTAssertTrue(httpClient.postTelemetryCalls.isEmpty)
        XCTAssertTrue(storage.removedSessionIds.isEmpty)
    }

    // MARK: - HTTP failure

    func testFlushDoesNotRemoveOnHttpFailure() async {
        storage.allRecords = [makeRecord(sessionId: "s1")]
        httpClient.errorToThrow = NSError(domain: "test", code: 500)

        await sut.flush(count: nil)

        XCTAssertTrue(storage.removedSessionIds.isEmpty)
    }

    // MARK: - Payload verification

    func testFlushSerializesMetricsArray() async {
        let record = makeRecord(sessionId: "s1")
        storage.allRecords = [record]

        await sut.flush(count: nil)

        let payload = httpClient.postTelemetryCalls.first!
        let array = try! JSONSerialization.jsonObject(with: payload) as! [[String: Any]]
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array.first?["sessionId"] as? String, "s1")
    }

    // MARK: - Accumulator reconciliation

    func testFlushAcknowledgesCurrentSessionAfterRemove() async {
        recordEvaluations(4)
        storage.allRecords = [makeRecord(sessionId: "s1", evaluationCount: 4)]

        await sut.flush(count: nil)
        await observer.persistNow()

        XCTAssertEqual(observerStorage.savedSessions.last?.metrics.runtime.evaluationCount, 0)
    }

    func testFlushDoesNotAcknowledgeOnHttpFailure() async {
        recordEvaluations(4)
        storage.allRecords = [makeRecord(sessionId: "s1", evaluationCount: 4)]
        httpClient.errorToThrow = NSError(domain: "test", code: 500)

        await sut.flush(count: nil)
        await observer.persistNow()

        XCTAssertEqual(observerStorage.savedSessions.last?.metrics.runtime.evaluationCount, 4)
    }

    func testFlushKeepsCountersRecordedWhileThePostWasInFlight() async {
        recordEvaluations(4)
        storage.allRecords = [makeRecord(sessionId: "s1", evaluationCount: 4)]

        await sut.flush(count: nil)
        recordEvaluations(3)
        await observer.persistNow()

        XCTAssertEqual(observerStorage.savedSessions.last?.metrics.runtime.evaluationCount, 3)
    }

    func testFlushIgnoresSessionsFromPreviousRuns() async {
        recordEvaluations(4)
        storage.allRecords = [makeRecord(sessionId: "old-session", evaluationCount: 9)]

        await sut.flush(count: nil)
        await observer.persistNow()

        XCTAssertEqual(observerStorage.savedSessions.last?.metrics.runtime.evaluationCount, 4)
    }

    // MARK: - Helpers

    private func recordEvaluations(_ count: Int) {
        let target = Target(matchingKey: "user1", trafficType: "user")
        for index in 0..<count {
            observer.notify(event: .evaluationRequested(flagName: "flag\(index)", target: target))
        }
    }

    private func makeRecord(sessionId: String, evaluationCount: Int = 0) -> TelemetrySessionRecord {
        TelemetrySessionRecord(sessionId: sessionId,
                               metrics: SessionMetricsDTO(sessionId: sessionId,
                                                          config: .init(syncMode: "streaming", pushRate: 60, evaluationRefreshRate: 300),
                                                          runtime: .init(evaluationCount: evaluationCount),
                                                          platform: .init()),
                                                          lastUpdateTimestamp: Date())
    }
}
