import XCTest
@testable import SplitThin

final class SplitClientConfigTest: XCTestCase {

    // MARK: - Default values

    func testDefaultValues() {
        let config = SplitClientConfig.builder().build()

        XCTAssertEqual(config.evaluationsRefreshRate, 3600)
        XCTAssertEqual(config.logLevel, .none)
        XCTAssertEqual(config.readyTimeout, 10)
        XCTAssertEqual(config.syncMode, .streaming)
        XCTAssertNil(config.serviceEndpoints)
        XCTAssertEqual(config.impressionsMode, .default)
        XCTAssertFalse(config.configsEnabled)
        XCTAssertNil(config.prefix)
        XCTAssertEqual(config.pushRate, 1800)
    }

    // MARK: - evaluationRefreshRate

    func testEvaluationRefreshRateClampedToMin() {
        let config = SplitClientConfig.builder()
                                      .set(evaluationRefreshRate: 10)
                                      .build()

        XCTAssertEqual(config.evaluationsRefreshRate, 60)
    }

    func testEvaluationRefreshRateAcceptsValidValue() {
        let config = SplitClientConfig.builder()
                                      .set(evaluationRefreshRate: 120)
                                      .build()

        XCTAssertEqual(config.evaluationsRefreshRate, 120)
    }

    func testEvaluationRefreshRateAcceptsMinBoundary() {
        let config = SplitClientConfig.builder()
                                      .set(evaluationRefreshRate: 60)
                                      .build()

        XCTAssertEqual(config.evaluationsRefreshRate, 60)
    }

    // MARK: - readyTimeout

    func testReadyTimeoutDefaultIs10() {
        let config = SplitClientConfig.builder().build()
        XCTAssertEqual(config.readyTimeout, 10)
    }

    func testReadyTimeoutZeroResetsToDefault() {
        let config = SplitClientConfig.builder()
                                      .set(readyTimeout: 0)
                                      .build()

        XCTAssertEqual(config.readyTimeout, 10)
    }

    func testReadyTimeoutNegativeResetsToDefault() {
        let config = SplitClientConfig.builder()
                                      .set(readyTimeout: -5)
                                      .build()

        XCTAssertEqual(config.readyTimeout, 10)
    }

    func testReadyTimeoutMinusOneIsAccepted() {
        let config = SplitClientConfig.builder()
                                      .set(readyTimeout: -1)
                                      .build()

        XCTAssertEqual(config.readyTimeout, -1)
    }

    func testReadyTimeoutPositiveIsAccepted() {
        let config = SplitClientConfig.builder()
                                      .set(readyTimeout: 30)
                                      .build()

        XCTAssertEqual(config.readyTimeout, 30)
    }

    // MARK: - prefix

    func testPrefixAcceptsValidAlphanumeric() {
        let config = SplitClientConfig.builder()
                                      .set(prefix: "my_prefix_123")
                                      .build()

        XCTAssertEqual(config.prefix, "my_prefix_123")
    }

    func testPrefixRejectsInvalidCharacters() {
        let config = SplitClientConfig.builder()
                                      .set(prefix: "invalid-prefix!")
                                      .build()

        XCTAssertNil(config.prefix)
    }

    func testPrefixRejectsEmptyString() {
        let config = SplitClientConfig.builder()
                                      .set(prefix: "")
                                      .build()

        XCTAssertNil(config.prefix)
    }

    func testPrefixRejectsTooLong() {
        let config = SplitClientConfig.builder()
                                      .set(prefix: String(repeating: "a", count: 81))
                                      .build()

        XCTAssertNil(config.prefix)
    }

    func testPrefixAcceptsMaxLength() {
        let config = SplitClientConfig.builder()
                                      .set(prefix: String(repeating: "a", count: 80))
                                      .build()

        XCTAssertEqual(config.prefix?.count, 80)
    }

    func testPrefixAcceptsSingleCharacter() {
        let config = SplitClientConfig.builder()
                                      .set(prefix: "a")
                                      .build()

        XCTAssertEqual(config.prefix, "a")
    }

    // MARK: - pushRate

    func testPushRateClampedToMin() {
        let config = SplitClientConfig.builder()
                                      .set(pushRate: 10)
                                      .build()

        XCTAssertEqual(config.pushRate, 30)
    }

    func testPushRateAcceptsValidValue() {
        let config = SplitClientConfig.builder()
                                      .set(pushRate: 600)
                                      .build()

        XCTAssertEqual(config.pushRate, 600)
    }

    func testPushRateAcceptsMinBoundary() {
        let config = SplitClientConfig.builder()
                                      .set(pushRate: 30)
                                      .build()

        XCTAssertEqual(config.pushRate, 30)
    }

    // MARK: - Enums

    func testSyncModeValues() {
        let polling = SplitClientConfig.builder().set(syncMode: .polling).build()
        XCTAssertEqual(polling.syncMode, .polling)

        let singleSync = SplitClientConfig.builder().set(syncMode: .singleSync).build()
        XCTAssertEqual(singleSync.syncMode, .singleSync)

        let streaming = SplitClientConfig.builder().set(syncMode: .streaming).build()
        XCTAssertEqual(streaming.syncMode, .streaming)
    }

    func testImpressionsModeValues() {
        let none = SplitClientConfig.builder().set(impressionsMode: .none).build()
        XCTAssertEqual(none.impressionsMode, .none)

        let defaultMode = SplitClientConfig.builder().set(impressionsMode: .default).build()
        XCTAssertEqual(defaultMode.impressionsMode, .default)
    }

    func testLogLevelValues() {
        for level in [LogLevel.none, .error, .warning, .info, .debug, .verbose] {
            let config = SplitClientConfig.builder().set(logLevel: level).build()
            XCTAssertEqual(config.logLevel, level)
        }
    }

    // MARK: - ServiceEndpoints

    func testServiceEndpointsCanBeSet() {
        let endpoints = ServiceEndpoints.builder()
                                        .set(sdkEndpoint: "https://custom.sdk.io")
                                        .build()

        let config = SplitClientConfig.builder()
                                      .set(serviceEndpoints: endpoints)
                                      .build()

        XCTAssertNotNil(config.serviceEndpoints)
    }

    // MARK: - configsEnabled

    func testConfigsEnabledCanBeEnabled() {
        let config = SplitClientConfig.builder()
                                      .set(configsEnabled: true)
                                      .build()

        XCTAssertTrue(config.configsEnabled)
    }

    // MARK: - evaluationFilters

    func testEvaluationFiltersDefaultsToNil() {
        let config = SplitClientConfig.builder().build()

        XCTAssertNil(config.evaluationFilters)
    }

    func testEvaluationFiltersCanBeSet() {
        let filters = EvaluationFilters(flagNames: ["flag_a"], flagSets: ["set_1"])

        let config = SplitClientConfig.builder()
                                      .set(evaluationFilters: filters)
                                      .build()

        XCTAssertEqual(config.evaluationFilters, filters)
    }

    // MARK: - Builder chaining

    func testBuilderChaining() {
        let config = SplitClientConfig.builder()
                                      .set(syncMode: .polling)
                                      .set(evaluationRefreshRate: 120)
                                      .set(readyTimeout: 30)
                                      .set(pushRate: 60)
                                      .set(logLevel: .debug)
                                      .set(configsEnabled: true)
                                      .build()

        XCTAssertEqual(config.syncMode, .polling)
        XCTAssertEqual(config.evaluationsRefreshRate, 120)
        XCTAssertEqual(config.readyTimeout, 30)
        XCTAssertEqual(config.pushRate, 60)
        XCTAssertEqual(config.logLevel, .debug)
        XCTAssertTrue(config.configsEnabled)
    }
}
