import Foundation
import Http
@testable import SplitThin

func buildFactory(httpClient: SecureHttpClient, syncMode: SyncMode = .singleSync, refreshRate: Int = 1, timeout: Int = -1, target: String = "user-123", fallbackTreatments: FallbackTreatmentsConfig? = nil) throws -> SplitFactory {

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
    builder.setSecureHttpClient(httpClient)

    guard let factory = builder.setSdkKey(SdkKey("test-sdk-key"))
                               .setTarget(target)
                               .setConfig(config)
                               .build() else {
        throw NSError(domain: "E2ETest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to build factory"])
    }

    return factory
}

func mockEvaluationsData(flags: [String]) -> Data {
    let evaluations = flags.map { flag in
        """
        {
            "featureName": "\(flag)",
            "treatment": "on",
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
