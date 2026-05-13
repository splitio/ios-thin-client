import XCTest
import Http
@testable import SplitThin

final class TelemetrySubmitterTests: XCTestCase {

    private var storage: TelemetryStorageMock!
    private var httpClient: SecureHttpClientMock!
    private var sut: DefaultTelemetrySubmitter!

    override func setUp() {
        super.setUp()
        storage = TelemetryStorageMock()
        httpClient = SecureHttpClientMock()
        sut = DefaultTelemetrySubmitter(storage: storage,
                                        secureHttpClient: httpClient,
                                        activeSessionId: "active-session")
    }

    // MARK: - Successful flush

    func testFlushPostsNonActiveSessionsAndRemovesThem() async {
        let record1 = makeRecord(sessionId: "s1")
        let record2 = makeRecord(sessionId: "s2")
        storage.nonActiveRecords = [record1, record2]

        await sut.flush(count: nil)

        XCTAssertEqual(httpClient.postTelemetryCalls.count, 1)
        XCTAssertEqual(storage.removedSessionIds.count, 1)
        XCTAssertEqual(storage.removedSessionIds.first, ["s1", "s2"])
        XCTAssertEqual(storage.getNonActiveCalledWith, "active-session")
    }

    func testFlushWithCountLimitsSessionsSent() async {
        storage.nonActiveRecords = [makeRecord(sessionId: "s1"), makeRecord(sessionId: "s2"), makeRecord(sessionId: "s3")]

        await sut.flush(count: 2)

        XCTAssertEqual(storage.removedSessionIds.first, ["s1", "s2"])
    }

    // MARK: - Empty storage

    func testFlushWithEmptyStorageIsNoOp() async {
        storage.nonActiveRecords = []

        await sut.flush(count: nil)

        XCTAssertTrue(httpClient.postTelemetryCalls.isEmpty)
        XCTAssertTrue(storage.removedSessionIds.isEmpty)
    }

    // MARK: - HTTP failure

    func testFlushDoesNotRemoveOnHttpFailure() async {
        storage.nonActiveRecords = [makeRecord(sessionId: "s1")]
        httpClient.errorToThrow = NSError(domain: "test", code: 500)

        await sut.flush(count: nil)

        XCTAssertTrue(storage.removedSessionIds.isEmpty)
    }

    // MARK: - Payload verification

    func testFlushSerializesMetricsArray() async {
        let record = makeRecord(sessionId: "s1")
        storage.nonActiveRecords = [record]

        await sut.flush(count: nil)

        let payload = httpClient.postTelemetryCalls.first!
        let array = try! JSONSerialization.jsonObject(with: payload) as! [[String: Any]]
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array.first?["sessionId"] as? String, "s1")
    }

    // MARK: - Helpers

    private func makeRecord(sessionId: String) -> TelemetrySessionRecord {
        TelemetrySessionRecord(sessionId: sessionId,
                               metrics: SessionMetricsDTO(sessionId: sessionId,
                                                          config: .init(syncMode: "streaming", pushRate: 60, evaluationRefreshRate: 300),
                                                          runtime: .init(),
                                                          platform: .init()),
                                                          lastUpdateTimestamp: Date())
    }
}
