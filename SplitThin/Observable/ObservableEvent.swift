import Foundation

// MARK: - Supporting types

enum FlushEntity: Sendable {
    case events
    case telemetry
}

enum HttpCategory: Sendable {
    case auth
    case evaluations
    case events
    case telemetry
}

enum ObservableHttpMethod: Sendable {
    case get
    case post
}

enum TrackDropReason: Sendable {
    case invalid
    case destroyed
}

enum EventsFlushReason: Sendable {
    case interval
    case queue
    case flush
}

// MARK: - Observable events

enum ObservableEvent: Sendable {

    // Existing events (used by SplitEventsManager)
    case evaluationsUpdated(SdkUpdateMetadata)
    case evaluationsLoadedFromCache(SdkReadyFromCacheMetadata)
    case sdkReadyTimeoutReached

    // Lifecycle
    case factoryInitStarted
    case factoryInitCompleted
    case clientCreated
    case targetSwitchStarted
    case targetSwitchCompleted
    case destroyStarted
    case destroyCompleted
    case flushStarted(FlushEntity)
    case flushCompleted(FlushEntity)
    case flushFailed(FlushEntity)
    case evaluationRequested(flagName: String, target: Target)
    case timeoutReached

    // Persistent storage
    case evalStorageLoadStarted
    case evalStorageLoadSucceeded(lastUpdateTimestamp: Int64?)
    case evalStorageLoadFailed
    case evalStorageWriteScheduled
    case evalStorageWriteSucceeded
    case evalStorageWriteFailed

    // Auth
    case jwtRequestStarted(cached: Bool)
    case jwtFetchStarted
    case jwtFetchSucceeded(expiresAt: Int64, pushEnabled: Bool)
    case jwtFetchFailedRetryable(statusCode: Int, attempt: Int, backoffMs: Int)
    case jwtFetchFailedNonRetryable(statusCode: Int)
    case jwtStored(secureStorage: Bool)
    case jwtExpiredOrInvalid

    // HTTP
    case httpRequestStarted(category: HttpCategory, method: ObservableHttpMethod)
    case httpRequestSucceeded(category: HttpCategory, statusCode: Int)
    case httpRequestFailedRetryable(category: HttpCategory, statusCode: Int)
    case httpRequestFailedNonRetryable(category: HttpCategory, statusCode: Int)
    case httpRetryExhausted(category: HttpCategory, statusCode: Int)

    // Evaluations synchronization
    case evalFetchRequested(reason: FetchReason)
    case evalFetchDeduped(reason: FetchReason)
    case evalFetchStarted(reason: FetchReason)
    case evalFetchSucceeded(changeNumber: Int64)
    case evalFetchFailed
    case evalDeserializeFailed
    case evalStorageUpdated(names: [String])

    // Sync mode
    case streamingConnectStarted
    case streamingConnected
    case streamingDisconnected
    case streamingNotificationReceived(notificationType: String)
    case pollTriggered(rate: Int)

    // Track events
    case trackCalled
    case trackDropped(reason: TrackDropReason)
    case eventsFlushTriggered(reason: EventsFlushReason)
    case eventsPostSucceeded(count: Int)
    case eventsPostFailed

    // App lifecycle (mobile)
    case syncPaused
    case syncResumed
    case streamingPaused
    case streamingResumed
}