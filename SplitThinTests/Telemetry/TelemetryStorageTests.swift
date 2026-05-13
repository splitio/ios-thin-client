import XCTest
@testable import SplitThin

final class TelemetryStorageTests: XCTestCase {

    private var coreDataStorage: CoreDataStorage!
    private var sut: DefaultTelemetryStorage!

    override func setUp() {
        super.setUp()
        coreDataStorage = CoreDataStorage(databaseName: "test_telemetry_\(UUID().uuidString)")
        sut = DefaultTelemetryStorage(storage: coreDataStorage)
    }

    // MARK: - Save and retrieve

    func testSaveAndGetAll() async {
        let metrics = makeMetrics(sessionId: "s1")
        await sut.save(sessionId: "s1", metrics: metrics)

        let records = await sut.getAll()

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.sessionId, "s1")
        XCTAssertEqual(records.first?.metrics.sessionId, "s1")
        XCTAssertEqual(records.first?.metrics.config.syncMode, "streaming")
    }

    func testSaveUpdatesExistingSession() async {
        var metrics = makeMetrics(sessionId: "s1")
        await sut.save(sessionId: "s1", metrics: metrics)

        metrics.runtime.evaluationCount = 99
        await sut.save(sessionId: "s1", metrics: metrics)

        let records = await sut.getAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.metrics.runtime.evaluationCount, 99)
    }

    // MARK: - FIFO eviction

    func testFifoEvictsOldestWhenExceedingMax() async {
        for i in 1...6 {
            let metrics = makeMetrics(sessionId: "s\(i)")
            await sut.save(sessionId: "s\(i)", metrics: metrics)
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms gap for timestamp ordering
        }

        let records = await sut.getAll()
        XCTAssertEqual(records.count, 5)

        let sessionIds = records.map { $0.sessionId }
        XCTAssertFalse(sessionIds.contains("s1"), "Oldest session should have been evicted")
        XCTAssertTrue(sessionIds.contains("s6"))
    }

    // MARK: - getNonActive

    func testGetNonActiveExcludesActiveSession() async {
        for i in 1...3 {
            await sut.save(sessionId: "s\(i)", metrics: makeMetrics(sessionId: "s\(i)"))
        }

        let records = await sut.getNonActive(activeSessionId: "s2")

        XCTAssertEqual(records.count, 2)
        let sessionIds = records.map { $0.sessionId }
        XCTAssertFalse(sessionIds.contains("s2"))
        XCTAssertTrue(sessionIds.contains("s1"))
        XCTAssertTrue(sessionIds.contains("s3"))
    }

    func testGetNonActiveReturnsEmptyWhenOnlyActiveExists() async {
        await sut.save(sessionId: "active", metrics: makeMetrics(sessionId: "active"))

        let records = await sut.getNonActive(activeSessionId: "active")

        XCTAssertTrue(records.isEmpty)
    }

    // MARK: - Remove

    func testRemoveDeletesSpecifiedSessions() async {
        for i in 1...3 {
            await sut.save(sessionId: "s\(i)", metrics: makeMetrics(sessionId: "s\(i)"))
        }

        await sut.remove(sessionIds: ["s1", "s3"])

        let records = await sut.getAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.sessionId, "s2")
    }

    func testRemoveWithEmptyArrayIsNoOp() async {
        await sut.save(sessionId: "s1", metrics: makeMetrics(sessionId: "s1"))

        await sut.remove(sessionIds: [])

        let records = await sut.getAll()
        XCTAssertEqual(records.count, 1)
    }

    // MARK: - Helpers

    private func makeMetrics(sessionId: String) -> SessionMetricsDTO {
        SessionMetricsDTO(sessionId: sessionId,
                          config: .init(syncMode: "streaming", pushRate: 60, evaluationRefreshRate: 300),
                          runtime: .init(),
                          platform: .init())
    }
}
