import Foundation

protocol Streaming: Sendable {
    func start() async
    func stop() async
}

final class DefaultStreaming: Streaming, @unchecked Sendable {

    private let fetchCoordinator: EvaluationFetchCoordinator
    private let secureHttpClient: SecureHttpClient
    private let target: Target

    init(fetchCoordinator: EvaluationFetchCoordinator, secureHttpClient: SecureHttpClient, target: Target) {
        self.fetchCoordinator = fetchCoordinator
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
