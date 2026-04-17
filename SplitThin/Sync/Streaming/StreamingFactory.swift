import Foundation
import Http
import BackoffCounter

struct StreamingComponents {
    let manager: StreamingManager
}

func createStreamingComponents(
    target: Target,
    authProvider: AuthProvider,
    streamingEndpoint: URL,
    httpClient: HttpClient,
    fetchCoordinator: EvaluationFetchCoordinator
) -> StreamingComponents {
    let manager = DefaultStreamingManager {
        DefaultStreamingConnectionManager(
            target: target,
            authProvider: authProvider,
            streamingEndpoint: streamingEndpoint,
            httpClient: httpClient,
            fetchCoordinator: fetchCoordinator,
            notificationParser: DefaultThinNotificationParser(),
            jwtParser: DefaultSseJwtParser(),
            backoffCounter: DefaultBackoffCounter(backoffBase: 1)
        )
    }
    return StreamingComponents(manager: manager)
}
