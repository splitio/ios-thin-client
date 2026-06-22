import Foundation
import Http
import Tracker
@testable import SplitThin

func buildFactory(httpClient: SecureHttpClient? = nil, retryableHttpClient: RetryableHttpClient? = nil, syncMode: SyncMode = .singleSync, refreshRate: Int = 1, readyTimeout: Int = -1, target: Target = Target(matchingKey: "user-123", trafficType: "user"), configsEnabled: Bool = false, prefix: String? = nil, fallbackTreatments: FallbackTreatmentsConfig? = nil, observer: Observer? = nil) throws -> SplitFactory {

    var configBuilder = SplitClientConfig.builder()
                                         .setMinEvaluationRefreshRate(1)
                                         .set(syncMode: syncMode)
                                         .set(evaluationRefreshRate: refreshRate)
                                         .set(readyTimeout: readyTimeout)
                                         .set(configsEnabled: configsEnabled)
                                         .set(prefix: prefix)

    if let fallbacks = fallbackTreatments {
        configBuilder = configBuilder.set(fallbackTreatments: fallbacks)
    }

    let config = configBuilder.build()

    // Factory
    let builder = DefaultSplitFactoryBuilder()

    // Inject the http layer (just possible on testing)
    if let httpClient {
        builder.setSecureHttpClient(httpClient)
    }
    if let retryableHttpClient {
        builder.setRetryableHttpClient(retryableHttpClient)
    }
    builder.setCredentialStorage(DefaultCredentialStorage())

    // Inject Observer (just possible on testing)
    if let observer = observer {
        builder.setFactoryObserver(observer)
    }

    guard let factory = builder.setSdkKey("test-sdk-key").setTarget(target).setConfig(config).build() else {
        throw NSError(domain: "E2ETest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to build factory"])
    }

    return factory
}

func buildClient(target: String = "user-123", treatmentsManager: TreatmentsManager? = nil, eventsManager: SplitEventsManager? = nil, authProvider: AuthProvider? = nil, observer: Observer? = nil, syncManager: SyncManager? = nil, tracker: Tracker? = nil, eventsTracker: EventsTracker? = nil, eventsScheduler: EventsPeriodicScheduler? = nil, telemetryObserver: TelemetryObserver? = nil, telemetrySubmitter: TelemetrySubmitter? = nil, fetchCoordinator: EvaluationFetchCoordinator? = nil) -> DefaultSplitClient {
    DefaultSplitClient(target: Target(matchingKey: target, trafficType: "user"),
                       treatmentsManager: treatmentsManager ?? TreatmentsManagerMock(),
                       eventsManager: eventsManager ?? SplitEventsManagerMock(),
                       authProvider: authProvider ?? AuthProviderMock(),
                       observer: observer ?? ObserverSpy(),
                       syncManager: syncManager ?? SyncManagerMock(),
                       tracker: tracker ?? TrackerMock(),
                       eventsTracker: eventsTracker ?? EventsTrackerMock(),
                       eventsScheduler: eventsScheduler ?? EventsPeriodicSchedulerMock(),
                       telemetryObserver: telemetryObserver ?? TelemetryObserver(storage: TelemetryStorageMock(), sessionId: "test", config: SplitClientConfig.builder().build()),
                       telemetrySubmitter: telemetrySubmitter ?? TelemetrySubmitterMock(),
                       fetchCoordinator: fetchCoordinator ?? EvaluationFetchCoordinatorMock())
}

func mockEvaluationsData(flags: [String], treatment: String = "on", config: String? = nil, since: Int64 = -1, till: Int64 = 12345) -> Data {
    let configField: String
    if let config {
        let escaped = config.replacingOccurrences(of: "\"", with: "\\\"")
        configField = "\"config\": \"\(escaped)\","
    } else {
        configField = ""
    }

    let evaluations = flags.map { flag in
        """
        {
            "flag": "\(flag)",
            "treatment": "\(treatment)",
            \(configField)
            "changeNumber": \(till),
            "sets": ["set-a"]
        }
        """
    }.joined(separator: ",")

    return """
    {
        "evaluations": [\(evaluations)],
        "since": \(since),
        "till": \(till)
    }
    """.data(using: .utf8)!
}

// Convenience init for some tests
func buildFactory(httpClient: SecureHttpClient, target: String = "user-123") throws -> SplitFactory {
    try buildFactory(httpClient: httpClient, target: Target(matchingKey: target, trafficType: "user"))
}