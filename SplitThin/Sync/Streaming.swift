import Foundation

protocol Streaming: Sendable {
    func start() async
    func stop() async
}

final class DefaultStreaming: Streaming, @unchecked Sendable {

    private let fetchCoordinator: EvaluationFetchCoordinator
    private let eventsManager: SplitEventsManager
    private let secureHttpClient: SecureHttpClient
    private let target: Target

    init(fetchCoordinator: EvaluationFetchCoordinator, eventsManager: SplitEventsManager, secureHttpClient: SecureHttpClient, target: Target) {
        self.fetchCoordinator = fetchCoordinator
        self.eventsManager = eventsManager
        self.secureHttpClient = secureHttpClient
        self.target = target
    }

    func start() async {
        // TODO: Implement SSE streaming connection
        // When streaming receives an update, call:
        // let metadata = SdkUpdateMetadata(type: .flagsUpdate, names: flagNames)
        // eventsManager.notifyInternalEvent(.evaluationsUpdated(metadata))
    }

    func stop() async {
        // TODO: Implement SSE streaming disconnection
    }
}
