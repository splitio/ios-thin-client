//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol SplitEventsManager: AnyObject, Sendable {
    func addListener(_ listener: SplitEventListener)
    func removeListener(_ listener: SplitEventListener)
    func notifyInternalEvent(_ event: SplitInternalEvent)
    func start()
    func stop()
    func isReady() -> Bool
}

final class DefaultSplitEventsManager: SplitEventsManager, @unchecked Sendable {

    private var listeners = [SplitEventListener]()

    private var sdkReadyMetadata: SdkReadyMetadata?
    private var sdkReadyFromCacheMetadata: SdkReadyFromCacheMetadata?
    private var sdkReadyTimedOutFired = false

    // Conditions that must be met before SDK_READY can fire.
    // Currently only one; future conditions (e.g., segments loaded) can be added here.
    private var evaluationsUpdateReceived = false

    private let processQueue = DispatchQueue(label: "split-evt-mngr-process")
    private let dataAccessQueue = DispatchQueue(label: "split-evt-mngr-data")
    private var isStarted = false
    private let timeoutSeconds: Int

    init(config: SplitClientConfig) {
        timeoutSeconds = config.timeout
    }

    func start() {
        dataAccessQueue.sync {
            guard !self.isStarted else { return }
            self.isStarted = true
        }

        // Unconditionally setup the timeOut timer, and check if sdkReady() later before firing the event
        if timeoutSeconds > 0 {
            DispatchQueue(label: "split-event-timedout").asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) { [weak self] in
                self?.notifyInternalEvent(.sdkReadyTimeoutReached)
            }
        }
    }

    func stop() {
        dataAccessQueue.async { [weak self] in
            self?.isStarted = false
        }
    }

    func isReady() -> Bool {
        dataAccessQueue.sync { sdkReadyMetadata != nil }
    }

    // MARK: - Register/remove listener
    func addListener(_ listener: SplitEventListener) {
        processQueue.async { [weak self] in
            guard let self else { return }
            self.appendListener(listener)

            // Sticky events: replay already-fired state to late subscribers
            if let metadata = self.getReadyMetadata() {
                DispatchQueue.main.async { listener.onReady(metadata) }
            }
            if let metadata = self.getCacheMetadata() {
                DispatchQueue.main.async { listener.onReadyFromCache(metadata) }
            }
        }
    }

    func removeListener(_ listener: SplitEventListener) {
        processQueue.async { [weak self] in
            guard let self else { return }
            self.deleteListener(listener)
        }
    }

    // MARK: - Notify internal events
    func notifyInternalEvent(_ event: SplitInternalEvent) {
        processQueue.async { [weak self] in
            guard let self, self.isRunning() else { return }
            Logger.d("SplitEventsManager: Event notified - \(self.formatEvent(event))")
            self.processEvent(event)
        }
    }

    private func formatEvent(_ event: SplitInternalEvent) -> String {
        switch event {
        case .evaluationsUpdated(let metadata):
            let names = metadata.names.joined(separator: ", ")
            return "evaluationsUpdated(type: \(metadata.type), names: [\(names)])"
        case .evaluationsLoadedFromCache(let metadata):
            return "evaluationsLoadedFromCache(lastUpdateTimestamp: \(metadata.lastUpdateTimestamp ?? -1), isInitialCacheLoad: \(metadata.isInitialCacheLoad))"
        case .sdkReadyTimeoutReached:
            return "sdkReadyTimeoutReached"
        }
    }

    // MARK: - Private
    private func processEvent(_ event: SplitInternalEvent) {
        switch event {
            case .evaluationsUpdated(let updateMetadata):
                setEvaluationsUpdateReceived()
                if isSdkReadyFired() {
                    if !updateMetadata.names.isEmpty {
                        triggerUpdate(updateMetadata)
                    }
                } else {
                    checkAndTriggerReady(changeNumber: updateMetadata.changeNumber)
                }

            case .evaluationsLoadedFromCache(let metadata):
                triggerReadyFromCache(metadata)

            case .sdkReadyTimeoutReached:
                if !isSdkReadyFired() {
                    triggerReadyTimedOut()
                }
        }
    }

    private func checkAndTriggerReady(changeNumber: Int64?) {
        if isEvaluationsUpdateReceived() {
            triggerReady(SdkReadyMetadata(lastUpdateTimestamp: changeNumber, isInitialCacheLoad: false))
        }
    }

    private func triggerReady(_ metadata: SdkReadyMetadata) {
        guard !isSdkReadyFired() else { return }
        setReadyMetadata(metadata)

        getListeners().forEach { listener in 
            DispatchQueue.main.async {  listener.onReady(metadata) } 
        }
    }

    private func triggerReadyFromCache(_ metadata: SdkReadyFromCacheMetadata) {
        guard !isSdkReadyFromCacheFired() else { return }
        setCacheMetadata(metadata)

        getListeners().forEach { listener in 
            DispatchQueue.main.async {  listener.onReadyFromCache(metadata) } 
        }
    }

    private func triggerReadyTimedOut() {
        guard !isSdkReadyTimedOutFired() else { return }
        setSdkReadyTimedOutFired()

        getListeners().forEach { listener in 
            DispatchQueue.main.async {  listener.onReadyTimedOut() } 
        }
    }

    private func triggerUpdate(_ metadata: SdkUpdateMetadata) {
        Logger.d("Triggering SDK event SDK_UPDATE")

        getListeners().forEach { listener in 
            DispatchQueue.main.async {  listener.onUpdate(metadata) } 
        }
    }

    // MARK: - Thread-safe accessors
    private func isRunning() -> Bool {
        dataAccessQueue.sync { isStarted }
    }

    private func isSdkReadyFired() -> Bool {
        dataAccessQueue.sync { sdkReadyMetadata != nil }
    }

    private func getReadyMetadata() -> SdkReadyMetadata? {
        dataAccessQueue.sync { sdkReadyMetadata }
    }

    private func setReadyMetadata(_ metadata: SdkReadyMetadata) {
        Logger.d("Triggering SDK event SDK_READY")
        dataAccessQueue.sync { sdkReadyMetadata = metadata }
    }

    private func isSdkReadyFromCacheFired() -> Bool {
        dataAccessQueue.sync { sdkReadyFromCacheMetadata != nil }
    }

    private func getCacheMetadata() -> SdkReadyFromCacheMetadata? {
        dataAccessQueue.sync { sdkReadyFromCacheMetadata }
    }

    private func setCacheMetadata(_ metadata: SdkReadyFromCacheMetadata) {
        Logger.d("Triggering SDK event SDK_READY_FROM_CACHE")
        dataAccessQueue.sync { sdkReadyFromCacheMetadata = metadata }
    }

    private func isSdkReadyTimedOutFired() -> Bool {
        dataAccessQueue.sync { sdkReadyTimedOutFired }
    }

    private func setSdkReadyTimedOutFired() {
        Logger.d("Triggering SDK event SDK_READY_TIMED_OUT")
        dataAccessQueue.sync { sdkReadyTimedOutFired = true }
    }

    private func isEvaluationsUpdateReceived() -> Bool {
        dataAccessQueue.sync { evaluationsUpdateReceived }
    }

    private func setEvaluationsUpdateReceived() {
        dataAccessQueue.sync { evaluationsUpdateReceived = true }
    }

    private func appendListener(_ listener: SplitEventListener) {
        dataAccessQueue.async { [weak self] in self?.listeners.append(listener) }
    }

    private func deleteListener(_ listener: SplitEventListener) {
        dataAccessQueue.async { [weak self] in
            // Comparing memory addresses to find the exact EventListener (not just one that has the same content)
            self?.listeners.removeElementByMemoryAddress(listener)
        }
    }

    private func getListeners() -> [SplitEventListener] {
        dataAccessQueue.sync { listeners }
    }
}

// MARK: - Observer conformance
extension DefaultSplitEventsManager: Observer {
    func notify(event: ObservableEvent) {
        switch event {
            case .evaluationsUpdated(let metadata):
                notifyInternalEvent(.evaluationsUpdated(metadata))
            case .evaluationsLoadedFromCache(let metadata):
                notifyInternalEvent(.evaluationsLoadedFromCache(metadata))
            case .sdkReadyTimeoutReached:
                notifyInternalEvent(.sdkReadyTimeoutReached)
            default:
                break
        }
    }
}