//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

final class TelemetryObserver: Observer, @unchecked Sendable {

    static let debounceInterval: TimeInterval = 10

    let sessionId: String
    private var metrics: SessionMetricsDTO
    private let storage: TelemetryWriteStorage
    private let lock = NSLock()
    private var debounceTask: Task<Void, Never>?

    init(storage: TelemetryWriteStorage, sessionId: String, config: SplitClientConfig) {
        self.storage = storage
        self.sessionId = sessionId
        self.metrics = SessionMetricsDTO(
            sessionId: sessionId,
            config: .init(
                syncMode: String(describing: config.syncMode),
                pushRate: config.pushRate,
                evaluationRefreshRate: config.pollingRate
            ),
            runtime: .init(),
            platform: .init()
        )
    }

    func notify(event: ObservableEvent) {
        let didUpdate = withLock(lock) { updateMetrics(for: event) }
        if didUpdate {
            schedulePersist()
        }
    }

    func persistNow() async {
        let snapshot: SessionMetricsDTO = withLock(lock) {
            debounceTask?.cancel()
            debounceTask = nil
            return metrics
        }
        await storage.save(sessionId: sessionId, metrics: snapshot)
    }

    // MARK: - Private

    private func updateMetrics(for event: ObservableEvent) -> Bool {
        switch event {
        case .jwtFetchSucceeded:
            metrics.runtime.successfulJwtFetches += 1
            return true
        case .evaluationRequested:
            metrics.runtime.evaluationCount += 1
            return true
        case .evalFetchSucceeded(let changeNumber):
            metrics.runtime.lastEvaluationsSync = changeNumber
            return true
        default:
            return false
        }
    }

    private func schedulePersist() {
        withLock(lock) {
            debounceTask?.cancel()
            let snapshot = metrics
            let sid = sessionId
            let store = storage
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(Self.debounceInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await store.save(sessionId: sid, metrics: snapshot)
            }
        }
    }
}
