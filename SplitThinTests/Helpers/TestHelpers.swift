import Foundation
import Http
import Tracker
@testable import SplitThin

func buildFactory(httpClient: SecureHttpClient, syncMode: SyncMode = .singleSync, refreshRate: Int = 1, timeout: Int = -1, target: Target = Target(matchingKey: "user-123", trafficType: "user"), fallbackTreatments: FallbackTreatmentsConfig? = nil, observer: Observer? = nil) throws -> SplitFactory {

    var configBuilder = SplitClientConfig.builder()
                                         .setMinEvaluationRefreshRate(1)
                                         .set(syncMode: syncMode)
                                         .set(evaluationRefreshRate: refreshRate)
                                         .set(timeout: timeout)

    if let fallbacks = fallbackTreatments {
        configBuilder = configBuilder.set(fallbackTreatments: fallbacks)
    }

    let config = configBuilder.build()

    // Factory
    let builder = DefaultSplitFactoryBuilder()

    // Inject httpClient (just possible on testing)
    builder.setSecureHttpClient(httpClient)
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

func buildClient(target: String = "user-123", treatmentsManager: TreatmentsManager? = nil, eventsManager: SplitEventsManager? = nil, authProvider: AuthProvider? = nil, observer: Observer? = nil, syncManager: SyncManager? = nil, tracker: Tracker? = nil, eventsTracker: EventsTracker? = nil, eventsScheduler: EventsPeriodicScheduler? = nil, telemetryObserver: TelemetryObserver? = nil, telemetrySubmitter: TelemetrySubmitter? = nil) -> DefaultSplitClient {
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
                       telemetrySubmitter: telemetrySubmitter ?? TelemetrySubmitterMock())
}

func mockEvaluationsData(flags: [String], treatment: String = "on", since: Int64 = -1, till: Int64 = 12345) -> Data {
    let evaluations = flags.map { flag in
        """
        {
            "featureName": "\(flag)",
            "treatment": "\(treatment)",
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