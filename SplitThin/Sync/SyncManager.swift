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
    private let eventsManager: SplitEventsManager
    private let polling: EvaluationPeriodicScheduler
    private let streaming: Streaming
    private let target: Target

    private var isPaused = false
    private let lock = NSLock()

    init(syncMode: SyncMode, evaluationRepository: EvaluationRepository, eventsManager: SplitEventsManager, periodicScheduler: EvaluationPeriodicScheduler, streaming: Streaming, target: Target) {
        self.syncMode = syncMode
        self.evaluationRepository = evaluationRepository
        self.eventsManager = eventsManager
        self.polling = periodicScheduler
        self.streaming = streaming
        self.target = target
    }

    func start() async {
        Logger.d("SyncManager: Starting with mode \(syncMode)")

        eventsManager.start()

        do {
            try await evaluationRepository.initialize(target: target)

            let flagNames = evaluationRepository.getFlagNames(target: target)
            let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: flagNames)
            eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))

            establishLink()
        } catch {
            // The timeout timer (already scheduled in eventsManager.start()) will take care of this scenario.
            Logger.e("SyncManager: Initial fetch failed: \(error)")
        }
    }

    private func establishLink() {
        switch syncMode {
            case .singleSync:
                // Already fetched
                return
            case .streaming:
                Task { await streaming.start() }
            case .polling:
                polling.start()
        }
    }

    func stop() async {
        Logger.d("SyncManager: Stopping")

        eventsManager.stop()
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
