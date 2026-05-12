//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

struct TelemetrySessionRecord: Sendable {
    let sessionId: String
    let metrics: SessionMetrics
    let lastUpdateTimestamp: Date
}

protocol TelemetryReadStorage: Sendable {
    func getAll() async -> [TelemetrySessionRecord]
    func getNonActive(activeSessionId: String) async -> [TelemetrySessionRecord]
}

protocol TelemetryWriteStorage: Sendable {
    func save(sessionId: String, metrics: SessionMetrics) async
    func remove(sessionIds: [String]) async
}

final class DefaultTelemetryStorage: TelemetryReadStorage, TelemetryWriteStorage, Sendable {

    static let maxStoredSessions = 5

    private let storage: CoreDataStorage

    init(storage: CoreDataStorage) {
        self.storage = storage
    }

    // MARK: - TelemetryWriteStorage

    func save(sessionId: String, metrics: SessionMetrics) async {
        guard let data = try? Json.encode(metrics),
              let json = String(data: data, encoding: .utf8) else {
            Logger.e("DefaultTelemetryStorage: Failed to serialize SessionMetrics")
            return
        }

        let timestamp = Date().timeIntervalSince1970
        try? await storage.upsertTelemetrySession(sessionId: sessionId, metricsJson: json, timestamp: timestamp)
        await storage.removeOldestTelemetrySessions(keepCount: Self.maxStoredSessions)
    }

    func remove(sessionIds: [String]) async {
        await storage.removeTelemetrySessions(sessionIds: sessionIds)
    }

    // MARK: - TelemetryReadStorage

    func getAll() async -> [TelemetrySessionRecord] {
        let rows = await storage.getAllTelemetrySessions()
        return rows.compactMap { row in
            deserialize(sessionId: row.sessionId, json: row.metricsJson, timestamp: row.lastUpdateTimestamp)
        }
    }

    func getNonActive(activeSessionId: String) async -> [TelemetrySessionRecord] {
        let rows = await storage.getTelemetrySessions(excluding: activeSessionId)
        return rows.compactMap { row in
            deserialize(sessionId: row.sessionId, json: row.metricsJson, timestamp: row.lastUpdateTimestamp)
        }
    }

    // MARK: - Private

    private func deserialize(sessionId: String, json: String, timestamp: Double) -> TelemetrySessionRecord? {
        guard let data = json.data(using: .utf8),
              let metrics = try? Json.decode(from: data, to: SessionMetrics.self) else {
            Logger.e("DefaultTelemetryStorage: Failed to deserialize SessionMetrics for session \(sessionId)")
            return nil
        }
        return TelemetrySessionRecord(sessionId: sessionId, metrics: metrics, lastUpdateTimestamp: Date(timeIntervalSince1970: timestamp))
    }
}
