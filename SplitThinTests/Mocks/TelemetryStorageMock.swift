import Foundation
@testable import SplitThin

final class TelemetryStorageMock: TelemetryReadStorage, TelemetryWriteStorage, @unchecked Sendable {

    var savedSessions = [(sessionId: String, metrics: SessionMetricsDTO)]()
    var removedSessionIds = [[String]]()
    var allRecords = [TelemetrySessionRecord]()
    var nonActiveRecords = [TelemetrySessionRecord]()
    var getNonActiveCalledWith: String?

    private let lock = NSLock()

    func save(sessionId: String, metrics: SessionMetricsDTO) async {
        withLock(lock) {
            savedSessions.append((sessionId, metrics))
        }
    }

    func remove(sessionIds: [String]) async {
        withLock(lock) {
            removedSessionIds.append(sessionIds)
        }
    }

    func getAll() async -> [TelemetrySessionRecord] {
        withLock(lock) { allRecords }
    }

    func getNonActive(activeSessionId: String) async -> [TelemetrySessionRecord] {
        withLock(lock) {
            getNonActiveCalledWith = activeSessionId
            return nonActiveRecords
        }
    }
}
