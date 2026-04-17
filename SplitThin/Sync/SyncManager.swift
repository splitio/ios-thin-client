import Foundation
import Logging

protocol SyncManager: Sendable {
    func start()
    func stop() async
}

protocol MobileSync: Sendable {
    func pause()
    func resume()
}

final class DefaultSyncManager: SyncManager, @unchecked Sendable {

    private let syncMode: SyncMode
    private let evaluationRepository: EvaluationRepository
    private let observer: Observer
    private let polling: EvaluationPeriodicScheduler
    private let streaming: Streaming
    private let target: Target

    // BG sync (just for mobile) 
    private var isPaused = false
    private let lock = NSLock()

    init(syncMode: SyncMode, evaluationRepository: EvaluationRepository, observer: Observer, periodicScheduler: EvaluationPeriodicScheduler, streaming: Streaming, target: Target, appStateManager: AppStateManager = DefaultAppStateManager.instance) {
        self.syncMode = syncMode
        self.evaluationRepository = evaluationRepository
        self.observer = observer
        self.polling = periodicScheduler
        self.streaming = streaming
        self.target = target

        appStateManager.addObserver(for: .didEnterBackground) { [weak self] in
            self?.pause()
        }
        appStateManager.addObserver(for: .didBecomeActive) { [weak self] in
            self?.resume()
        }
    }

    func start() {

        Task { // Fire and forget

            Logger.d("SyncManager: Starting with mode \(syncMode)")

            do {
                try await evaluationRepository.initialize(target: target)

                let flagNames = evaluationRepository.getFlagNames(target: target)
                let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: flagNames)
                try? observer.notify(event: .evaluationsUpdated(metadata))

                establishLink()
            } catch {
                // The timeout timer (already scheduled in eventsManager.start()) will take care of this scenario.
                Logger.e("SyncManager: Initial fetch failed: \(error)")
            }
        }
    }

    func stop() async {
        Logger.d("SyncManager: Stopping")

        polling.stop()
        await streaming.stop()
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
}

// MARK: BG Sync (just for mobile devices)
extension DefaultSyncManager: MobileSync {
    func pause() {
        #if !os(macOS)
            withLock(lock) {
                guard !isPaused else { return }

                polling.stop()
                streaming.pause()

                isPaused = true
                Logger.d("SyncManager: Paused")
            }
        #endif
    }

    func resume() {
        #if !os(macOS)
            withLock(lock) {
                guard isPaused else { return }
                
                switch syncMode {
                    case .singleSync:
                        break
                    case .polling:
                        polling.start()
                    case .streaming:
                        streaming.resume()
                }

                isPaused = false
                Logger.d("SyncManager: Resumed")
            }
        #endif
    }
}