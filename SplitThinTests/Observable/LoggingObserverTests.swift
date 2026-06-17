import XCTest
@testable import SplitThin

final class LoggingObserverTests: XCTestCase {

    private var observer: LoggingObserver!

    override func setUp() {
        super.setUp()
        observer = LoggingObserver()
    }

    func testAllEventsHandledWithoutCrash() {
        let target = Target(matchingKey: "key", trafficType: "user")
        let allEvents: [ObservableEvent] = [
            // Existing
            .evaluationsUpdated(SdkUpdateMetadata(type: .flagsUpdate, names: ["f1"])),
            .evaluationsLoadedFromCache(SdkReadyFromCacheMetadata(lastUpdateTimestamp: nil, isInitialCacheLoad: true)),
            .sdkReadyTimeoutReached,

            // Lifecycle
            .factoryInitStarted,
            .factoryInitCompleted,
            .clientCreated,
            .targetSwitchStarted,
            .targetSwitchCompleted,
            .destroyStarted,
            .destroyCompleted,
            .flushStarted(.events),
            .flushCompleted(.telemetry),
            .flushFailed(.events),
            .evaluationRequested(flagName: "flag1", target: target),
            .timeoutReached,

            // Persistent storage
            .evalStorageLoadStarted,
            .evalStorageLoadSucceeded(lastUpdateTimestamp: 123456),
            .evalStorageLoadSucceeded(lastUpdateTimestamp: nil),
            .evalStorageLoadFailed,
            .evalStorageWriteScheduled,
            .evalStorageWriteSucceeded,
            .evalStorageWriteFailed,

            // Auth
            .jwtRequestStarted(cached: true),
            .jwtFetchStarted,
            .jwtFetchSucceeded(expiresAt: 999, pushEnabled: true),
            .jwtFetchFailedRetryable(statusCode: 500, attempt: 2, backoffMs: 1000),
            .jwtFetchFailedNonRetryable(statusCode: 401),
            .jwtStored(secureStorage: false),
            .jwtExpiredOrInvalid,

            // HTTP
            .httpRequestStarted(category: .evaluations, method: ObservableHttpMethod.get),
            .httpRequestSucceeded(category: .auth, statusCode: 200),
            .httpRequestFailedRetryable(category: .events, statusCode: 503),
            .httpRequestFailedNonRetryable(category: .telemetry, statusCode: 400),
            .httpRetryExhausted(category: .evaluations, statusCode: 500),

            // Evaluations sync
            .evalFetchRequested(reason: .initialization),
            .evalFetchDeduped(reason: .periodic),
            .evalFetchStarted(reason: .push),
            .evalFetchSucceeded(changeNumber: 42),
            .evalFetchFailed,
            .evalDeserializeFailed,
            .evalStorageUpdated(names: ["flag1", "flag2"]),

            // Sync mode
            .streamingConnectStarted,
            .streamingConnected,
            .streamingDisconnected,
            .streamingNotificationReceived(notificationType: "SPLIT_UPDATE"),
            .pollTriggered(rate: 60),

            // Track events
            .trackCalled,
            .trackDropped(reason: .invalid),
            .eventsFlushTriggered(reason: .queue),
            .eventsPostSucceeded(count: 5),
            .eventsPostFailed,

            // App lifecycle
            .syncPaused,
            .syncResumed,
            .streamingPaused,
            .streamingResumed,
        ]

        for event in allEvents {
            observer.notify(event: event)
        }
    }

    func testWorksWithEventDispatcher() {
        let dispatcher = EventDispatcher()
        dispatcher.register(observer)

        dispatcher.notify(event: .factoryInitStarted)
        dispatcher.notify(event: .httpRequestStarted(category: .auth, method: .get))
        dispatcher.notify(event: .evalFetchSucceeded(changeNumber: 1))
    }
}
