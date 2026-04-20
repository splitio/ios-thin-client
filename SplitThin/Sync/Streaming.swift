import Foundation
import Logging

protocol Streaming: Sendable {
    func start() async
    func stop() async
}

final class DefaultStreaming: Streaming, @unchecked Sendable {

    // Components
    private let fetchCoordinator: EvaluationFetchCoordinator
    private let observer: Observer // For SDK events & logging
    private let secureHttpClient: SecureHttpClient
    private let target: Target

    // BG pause sync
    private var isPaused = false
    private let lock = NSLock()

    init(fetchCoordinator: EvaluationFetchCoordinator, observer: Observer, secureHttpClient: SecureHttpClient, target: Target) {
        self.fetchCoordinator = fetchCoordinator
        self.observer = observer
        self.secureHttpClient = secureHttpClient
        self.target = target
    }

    func start() async {
        observer.notify(event: .streamingConnectStarted)
        // TODO: Implement SSE streaming connection
    }

    func stop() async {
        observer.notify(event: .streamingDisconnected)
        // TODO: Implement SSE streaming disconnection
    }
}

// MARK: BG Sync (just for mobile devices)
extension DefaultStreaming: MobileSync {
    func pause() {
        withLock(lock) {
            guard !isPaused else { return }

            // TODO: Disconnect SSE when implemented
            isPaused = true
            observer.notify(event: .streamingPaused)
            Logger.d("Streaming: Paused")
        }
    }

    func resume() {
        withLock(lock) {
            guard isPaused else { return }

            // TODO: Reconnect SSE when implemented
            isPaused = false
            observer.notify(event: .streamingResumed)
            Logger.d("Streaming: Resumed")
        }
    }
}