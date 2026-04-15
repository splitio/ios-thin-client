import Foundation
import Logging

protocol Streaming: Sendable {
    func start() async
    func stop() async
}

final class DefaultStreaming: Streaming, @unchecked Sendable {

    // Components
    private let fetchCoordinator: EvaluationFetchCoordinator
    private let eventsManager: SplitEventsManager
    private let secureHttpClient: SecureHttpClient
    private let target: Target

    // BG pause sync
    private var isPaused = false
    private let lock = NSLock()

    init(fetchCoordinator: EvaluationFetchCoordinator, eventsManager: SplitEventsManager, secureHttpClient: SecureHttpClient, target: Target) {
        self.fetchCoordinator = fetchCoordinator
        self.eventsManager = eventsManager
        self.secureHttpClient = secureHttpClient
        self.target = target
    }

    func start() async {
        // TODO: Implement SSE streaming connection
    }

    func stop() async {
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
            Logger.d("Streaming: Paused")
        }
    }

    func resume() {
        withLock(lock) {
            guard isPaused else { return }

            // TODO: Reconnect SSE when implemented
            isPaused = false
            Logger.d("Streaming: Resumed")
        }
    }
}