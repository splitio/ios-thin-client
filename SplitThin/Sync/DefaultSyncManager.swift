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
    private let evaluationRepository: EvaluationRepository
    private let polling: EvaluationPeriodicScheduler
    private let streaming: Streaming
    private let target: Target

    private var isPaused = false
    private let lock = NSLock()

    init(syncMode: SyncMode, evaluationRepository: EvaluationRepository, periodicScheduler: EvaluationPeriodicScheduler, streaming: Streaming, target: Target) {
        self.syncMode = syncMode
        self.evaluationRepository = evaluationRepository
        self.polling = periodicScheduler
        self.streaming = streaming
        self.target = target
    }

    func start() async {
        Logger.d("SyncManager: Starting with mode \(syncMode)")

        await evaluationRepository.initialize(target: target)

        switch syncMode {
            case .singleSync:
                // Already fetched
                break
            case .streaming:
                await streaming.start()
            case .polling:
                polling.start()
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
