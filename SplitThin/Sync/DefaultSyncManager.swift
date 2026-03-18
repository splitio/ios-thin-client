import Foundation
import Logging

protocol SyncManager: Sendable {
    func start() async
    func stop() async
    func pause()
    func resume()
}

final class DefaultSyncManager: SyncManager, @unchecked Sendable {

    private let syncMode: SyncMode
    private let evaluationProvider: EvaluationProvider
    private let polling: EvaluationPeriodicScheduler
    private let streaming: Streaming
    private let target: Target
    private let filters: EvaluationFilters?

    private var isPaused = false
    private let lock = NSLock()

    init(syncMode: SyncMode, evaluationProvider: EvaluationProvider, periodicScheduler: EvaluationPeriodicScheduler, streaming: Streaming, target: Target, filters: EvaluationFilters?) {
        self.syncMode = syncMode
        self.evaluationProvider = evaluationProvider
        self.polling = periodicScheduler
        self.streaming = streaming
        self.target = target
        self.filters = filters
    }

    func start() async {
        Logger.d("SyncManager: Starting with mode \(syncMode)")

        await evaluationProvider.fetchAndUpdate(target: target, filters: filters)

        switch syncMode {
            case .streaming:
                await streaming.start()
            case .polling:
                polling.start()
            case .singleSync:
                break
        }
    }

    func stop() async {
        Logger.d("SyncManager: Stopping")

        polling.stop()
        await streaming.stop()
    }

    func pause() {
        withLock(lock) { isPaused = true }
        polling.stop()
        Logger.d("SyncManager: Paused")
    }

    func resume() {
        let wasPaused = withLock(lock) {
            let was = isPaused
            isPaused = false
            return was
        }

        if wasPaused && syncMode != .singleSync {
            polling.start()
            Logger.d("SyncManager: Resumed")
        }
    }
}
