import Foundation
import Http
@testable import SplitThin

func buildFactory(httpClient: SecureHttpClient, syncMode: SyncMode = .singleSync, refreshRate: Int = 1, timeout: Int = -1, target: String = "user-123", fallbackTreatments: FallbackTreatmentsConfig? = nil, observer: Observer? = nil) throws -> SplitFactory {

    // SplitConfig
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

    // Inject Observer (just possible on testing)
    if let observer = observer {
        builder.setFactoryObserver(observer)
    }

    guard let factory = builder.setSdkKey("test-sdk-key")
                               .setTarget(target)
                               .setConfig(config)
                               .build() else {
        throw NSError(domain: "E2ETest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to build factory"])
    }

    return factory
}

func buildClient(target: String = "user-123", treatmentsManager: TreatmentsManager? = nil, eventsManager: SplitEventsManager? = nil, observer: Observer? = nil, syncManager: SyncManager? = nil) -> DefaultSplitClient {
    DefaultSplitClient(target: Target(matchingKey: target),
                       treatmentsManager: treatmentsManager ?? TreatmentsManagerMock(),
                       eventsManager: eventsManager ?? SplitEventsManagerMock(),
                       observer: observer ?? ObserverSpy(),
                       syncManager: syncManager ?? SyncManagerMock())
}

func mockEvaluationsData(flags: [String], treatment: String = "on") -> Data {
    let evaluations = flags.map { flag in
        """
        {
            "featureName": "\(flag)",
            "treatment": "\(treatment)",
            "label": "default rule",
            "changeNumber": 12345,
            "sets": ["set-a"]
        }
        """
    }.joined(separator: ",")

    return """
    {
        "evaluations": [\(evaluations)],
        "since": -1,
        "till": 12345
    }
    """.data(using: .utf8)!
}
