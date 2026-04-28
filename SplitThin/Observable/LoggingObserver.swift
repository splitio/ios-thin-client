//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

final class LoggingObserver: Observer, @unchecked Sendable {

    private let logger: Logger

    init(logger: Logger = Logger.shared) {
        self.logger = logger
    }

    func notify(event: ObservableEvent) {
        switch event {

            // Existing events (handled by SplitEventsManager, logged here too)
            case .evaluationsUpdated(let metadata):
                Logger.i("Evaluations updated (\(metadata.names.count) flags)")
            case .evaluationsLoadedFromCache:
                Logger.i("Evaluations loaded from cache")
            case .sdkReadyTimeoutReached:
                Logger.d("SDK timeout reached")

            // Lifecycle
            case .factoryInitStarted:
                Logger.i("Init started")
            case .factoryInitCompleted:
                Logger.i("Init completed")
            case .clientCreated:
                Logger.d("Client created")
            case .targetSwitchStarted:
                Logger.i("Target switch started")
            case .targetSwitchCompleted:
                Logger.i("Target switch complete")
            case .destroyStarted:
                Logger.i("Destroy started")
            case .destroyCompleted:
                Logger.i("Destroy completed")
            case .flushStarted(let entity):
                Logger.i("Flush started for \(entity)")
            case .flushCompleted(let entity):
                Logger.i("Flush completed for \(entity)")
            case .flushFailed(let entity):
                Logger.w("Flush failed \(entity)")
            case .evaluationRequested(let flagName, _):
                Logger.d("Evaluation requested for \(flagName)")
            case .timeoutReached:
                Logger.d("SDK timeout reached")

            // Persistent storage
            case .evalStorageLoadStarted:
                Logger.d("Loading evaluations from persistent storage")
            case .evalStorageLoadSucceeded(let timestamp):
                Logger.i("Loaded evaluations from storage (lastUpdate: \(timestamp.map(String.init) ?? "none"))")
            case .evalStorageLoadFailed:
                Logger.w("Failed to load evaluations from storage")
            case .evalStorageWriteScheduled:
                Logger.d("Persisting evaluations")
            case .evalStorageWriteSucceeded:
                Logger.d("Persisted evaluations")
            case .evalStorageWriteFailed:
                Logger.w("Failed to persist evaluations")

            // Auth
            case .jwtRequestStarted(let cached):
                Logger.d("JWT requested (cached: \(cached))")
            case .jwtFetchStarted:
                Logger.d("Fetching JWT")
            case .jwtFetchSucceeded(let expiresAt, let pushEnabled):
                Logger.i("JWT fetched (push enabled: \(pushEnabled), expiresAt: \(expiresAt))")
            case .jwtFetchFailedRetryable(let statusCode, let attempt, let backoffMs):
                Logger.w("JWT fetch failed, will retry (status: \(statusCode), attempt: \(attempt), backoff: \(backoffMs)ms)")
            case .jwtFetchFailedNonRetryable(let statusCode):
                Logger.e("JWT fetch failed (status: \(statusCode))")
            case .jwtStored(let secureStorage):
                Logger.d("JWT stored (secureStorage: \(secureStorage))")
            case .jwtExpiredOrInvalid:
                Logger.i("JWT expired/invalid, refreshing")

            // HTTP
            case .httpRequestStarted(let category, let method):
                Logger.d("HTTP \(category) \(method) started")

            case .httpRequestSucceeded(let category, let statusCode):
                Logger.d("HTTP success (\(category), status: \(statusCode))")
            case .httpRequestFailedRetryable(let category, let statusCode):
                Logger.w("HTTP failed for \(category), retrying (status: \(statusCode))")
            case .httpRequestFailedNonRetryable(let category, let statusCode):
                Logger.e("HTTP failed for \(category) (status: \(statusCode))")
            case .httpRetryExhausted(let category, let statusCode):
                Logger.e("Retry attempts exhausted for \(category) (status: \(statusCode))")

            // Evaluations synchronization
            case .evalFetchRequested(let reason):
                Logger.i("Evaluations fetch requested (reason: \(reason))")
            case .evalFetchDeduped(let reason):
                Logger.d("Evaluations fetch deduped (awaiting fetch in progress, reason: \(reason))")
            case .evalFetchStarted(let reason):
                Logger.i("Evaluations fetch started (reason: \(reason))")
            case .evalFetchSucceeded(let changeNumber):
                Logger.i("Evaluations fetch succeeded (changeNumber: \(changeNumber))")
            case .evalFetchFailed:
                Logger.w("Evaluations fetch failed")
            case .evalDeserializeFailed:
                Logger.e("Failed to parse evaluations response")
            case .evalStorageUpdated(let names):
                Logger.d("Evaluations applied to in-memory storage (\(names.count) flags)")

            // Sync mode
            case .streamingConnectStarted:
                Logger.i("Streaming connect started")
            case .streamingConnected:
                Logger.i("Streaming connected")
            case .streamingDisconnected:
                Logger.i("Streaming disconnected")
            case .streamingNotificationReceived(let notificationType):
                Logger.d("Streaming notification received (\(notificationType))")
            case .pollTriggered(let rate):
                Logger.d("Polling (rate: \(rate))")

            // Track events
            case .trackCalled:
                Logger.d("Track called")
            case .trackDropped(let reason):
                Logger.d("Track dropped (reason: \(reason))")
            case .eventsFlushTriggered(let reason):
                Logger.d("Events flush triggered (reason: \(reason))")
            case .eventsPostSucceeded(let count):
                Logger.i("Events posted (count: \(count))")
            case .eventsPostFailed:
                Logger.w("Events post failed")

            // App lifecycle (mobile)
            case .syncPaused:
                Logger.i("Sync paused (reason: app background)")
            case .syncResumed:
                Logger.i("Sync resumed")
            case .streamingPaused:
                Logger.i("Streaming paused")
            case .streamingResumed:
                Logger.i("Streaming resumed")
        }
    }
}
