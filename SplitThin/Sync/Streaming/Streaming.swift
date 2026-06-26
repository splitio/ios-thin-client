//  Created by Gaston Thea
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging
import Http
import Streaming
import BackoffCounter

protocol Streaming {
    func start()
    func stop() async
    func pause()
    func resume()
    func handleNotification(_ notification: ThinNotification)
    func setPushDisabledHandler(_ handler: @escaping () -> Void)
}

final class DefaultStreaming: Streaming, SseHandler, @unchecked Sendable {

    private enum State { case stopped, started, paused }

    private let target: Target
    private let authProvider: AuthProvider?
    private let streamingEndpoint: URL?
    private let httpClient: HttpClient?
    private let fetchCoordinator: EvaluationFetchCoordinator
    private let notificationParser: ThinNotificationParser
    private let jwtParser: SseJwtParser?
    private let backoffCounter: BackoffCounter?
    private let payloadDecoder: PayloadDecoder
    private let onConnect: (() -> Void)?
    private var onPushDisabled: (() -> Void)?

    private var state: State = .stopped
    private let stateLock = NSLock()
    private var activeConnectionHandler: SseConnectionHandler?
    private var isConnecting = false // dedups concurrent connectSse attempts
    private var reconnectTask: Task<Void, Never>? // ensures only one reconnect runs

    init(target: Target, authProvider: AuthProvider, streamingEndpoint: URL, httpClient: HttpClient, fetchCoordinator: EvaluationFetchCoordinator, notificationParser: ThinNotificationParser, jwtParser: SseJwtParser, backoffCounter: BackoffCounter, payloadDecoder: PayloadDecoder = DefaultPayloadDecoder(), onConnect: (() -> Void)? = nil) {
        self.target = target
        self.authProvider = authProvider
        self.streamingEndpoint = streamingEndpoint
        self.httpClient = httpClient
        self.fetchCoordinator = fetchCoordinator
        self.notificationParser = notificationParser
        self.jwtParser = jwtParser
        self.backoffCounter = backoffCounter
        self.payloadDecoder = payloadDecoder
        self.onConnect = onConnect
        self.onPushDisabled = nil
    }

    // MARK: Init for testing (doesn't need connection)
    #if DEBUG
    init(target: Target, fetchCoordinator: EvaluationFetchCoordinator, notificationParser: ThinNotificationParser, payloadDecoder: PayloadDecoder = DefaultPayloadDecoder(), onPushDisabled: (() -> Void)? = nil) {
        self.target = target
        self.fetchCoordinator = fetchCoordinator
        self.notificationParser = notificationParser
        self.payloadDecoder = payloadDecoder
        self.onPushDisabled = onPushDisabled

        // All nil
        self.authProvider = nil
        self.streamingEndpoint = nil
        self.httpClient = nil
        self.jwtParser = nil
        self.backoffCounter = nil
        self.onConnect = nil
    }
    #endif

    func start() {
        let shouldStart: Bool = withLock(stateLock) {
            guard state == .stopped else { return false }
            state = .started
            return true
        }
        guard shouldStart else { return }
        Task { [weak self] in await self?.connectSse() }
    }

    func stop() {
        teardown(movingTo: .stopped)
    }

    func pause() {
        teardown(movingTo: .paused)
    }

    private func teardown(movingTo newState: State) {
        withLock(stateLock) {
            state = newState
            reconnectTask?.cancel()
            reconnectTask = nil
            activeConnectionHandler?.disconnect()
            activeConnectionHandler = nil
        }
    }

    func resume() {
        let shouldResume: Bool = withLock(stateLock) {
            guard state == .paused else { return false }
            state = .started
            return true
        }
        guard shouldResume else { return }
        Task { [weak self] in await self?.connectSse() }
    }

    func setPushDisabledHandler(_ handler: @escaping () -> Void) {
        withLock(stateLock) { self.onPushDisabled = handler }
    }

    private func notifyPushDisabled() {
        let handler = withLock(stateLock) { onPushDisabled }
        handler?()
    }

    func handleNotification(_ notification: ThinNotification) {
        switch notification.type {
            case .evaluationUpdate:
                if let evalNotification = notification as? EvaluationUpdateNotification {
                    Task { [weak self] in
                        guard let self else { return }
                        await self.handleEvaluationUpdate(evalNotification)
                    }
                }
            case .control:
                handleControl(notification as? ThinControlNotification)
            case .occupancy:
                if let occupancy = notification as? ThinOccupancyNotification, occupancy.publishers == 0 {
                    notifyPushDisabled()
                }
            case .error:
                if let error = notification as? ThinStreamingError {
                    reportError(isRetryable: error.isRetryable)
                }
        }
    }

    // MARK: - SseHandler

    func isConnectionConfirmed(message: [String: String]) -> Bool {
        message["id"] != nil || message["data"] != nil
    }

    func handleIncomingMessage(message: [String: String]) {
        guard let data = message["data"] else { return }

        let channel = message["channel"] ?? ""
        let timestamp = Int64(message["timestamp"] ?? "0") ?? 0
        let raw = RawThinNotification(channel: channel, data: data, timestamp: timestamp)
        guard let notification = notificationParser.parse(raw: raw) else { return }
        handleNotification(notification)
    }

    func reportError(isRetryable: Bool) {
        Logger.w("StreamingConnection: SSE error, retryable=\(isRetryable)")
        guard isRetryable else {
            teardown(movingTo: .stopped)
            return
        }

        withLock(stateLock) {
            guard state == .started else { return }
            reconnectTask?.cancel()
            reconnectTask = Task { [weak self] in
                guard let self else { return }
                let delay = backoffCounter?.getNextRetryTime() ?? 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await connectSse()
            }
        }
    }

    // MARK: - Evaluation update strategies

    private func handleEvaluationUpdate(_ notification: EvaluationUpdateNotification) async {
        let typeName = notification.dataType.map(String.init(describing:)) ?? "unknown"
        Logger.d("StreamingConnection: evaluation update received (dataType: \(typeName))")

        let delay = refetchDelay(from: notification)

        switch notification.updateStrategy {
            case .boundedFetchRequest:
                await handleBounded(notification, delay: delay)
            case .keyList:
                await handleKeyList(notification, delay: delay)
            default:
                await fetchCoordinator.refetchAll(delay: delay)
        }
    }

    private func handleBounded(_ notification: EvaluationUpdateNotification, delay: RefetchDelay) async {
        guard let payload = notification.payload else {
            Logger.w("StreamingConnectionManager: bounded notification missing payload, falling back to fetchAll")
            await fetchCoordinator.refetchAll(delay: delay)
            return
        }

        do {
            let keyMap = try payloadDecoder.decodeAsBytes(payload: payload, compressionType: notification.compressionType)
            let affectedKeys = fetchCoordinator.registeredMatchingKeys.filter { key in
                payloadDecoder.isKeyInBitmap(keyMap: keyMap, hashedKey: payloadDecoder.hashKey(key))
            }
            await fetchCoordinator.refetchKeys(Set(affectedKeys), delay: delay)
        } catch {
            Logger.e("StreamingConnectionManager: error decoding bounded payload: \(error). Falling back to fetchAll")
            await fetchCoordinator.refetchAll(delay: delay)
        }
    }

    private func handleKeyList(_ notification: EvaluationUpdateNotification, delay: RefetchDelay) async {
        guard let payload = notification.payload else {
            Logger.w("StreamingConnectionManager: keyList notification missing payload, falling back to fetchAll")
            await fetchCoordinator.refetchAll(delay: delay)
            return
        }

        do {
            let jsonString = try payloadDecoder.decodeAsString(payload: payload, compressionType: notification.compressionType)
            let keyList = try payloadDecoder.parseKeyList(jsonString: jsonString)
            let affectedHashes = keyList.added.union(keyList.removed)

            let affectedKeys = fetchCoordinator.registeredMatchingKeys.filter { key in
                affectedHashes.contains(payloadDecoder.hashKey(key))
            } 
            await fetchCoordinator.refetchKeys(Set(affectedKeys), delay: delay)
        } catch {
            Logger.e("StreamingConnectionManager: error decoding keyList payload: \(error). Falling back to fetchAll")
            await fetchCoordinator.refetchAll(delay: delay)
        }
    }

    private func refetchDelay(from notification: EvaluationUpdateNotification) -> RefetchDelay {
        guard let intervalMs = notification.updateIntervalMs, let seed = notification.algorithmSeed else { return .none }

        return RefetchDelay(intervalMs: intervalMs, seed: seed)
    }

    // MARK: - Private

    private func connectSse() async {
        guard let authProvider, let jwtParser, let streamingEndpoint, let httpClient else { return }

        // Only connect while started (not paused/stopped) and if not already connecting.
        let shouldConnect: Bool = withLock(stateLock) {
            guard state == .started, !isConnecting else { return false }
            isConnecting = true
            return true
        }
        guard shouldConnect else { return }
        defer { withLock(stateLock) { isConnecting = false } }

        // Connect
        do {
            let credential = try await authProvider.getCredential()
            guard credential.pushEnabled else {
                Logger.d("StreamingConnection: push not enabled")
                notifyPushDisabled()
                return
            }

            if let delay = credential.connDelay, delay > 0 {
                Logger.d("StreamingConnection: delaying connection by \(delay)s")
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                // Bail if we were paused/stopped while waiting (CAT-3: don't open in background).
                guard withLock(stateLock, { state == .started }) else { return }
            }

            guard let channels = jwtParser.extractChannels(from: credential.token), !channels.isEmpty else {
                Logger.w("StreamingConnection: no channels in JWT")
                return
            }

            let kAblySplitSdkClientKeyLength = 4
            
            let endpoint = Endpoint.builder(baseUrl: streamingEndpoint, path: "sse").set(method: .get).add(headers:
                                                                                                ["Content-Type":"text/event-stream",
                                                                                                 "SplitSDKClientKey": "\(String("apiKey".suffix(kAblySplitSdkClientKeyLength)))",
                                                                                                 "SplitSDKVersion":"\(Version.semantic)"]).build()
            let factory = DefaultSseClientFactory(endpoint: endpoint, httpClient: httpClient, sseHandler: self)
            let handler = SseConnectionHandler(sseClientFactory: factory)
            withLock(stateLock) { activeConnectionHandler = handler }

            handler.connect(token: credential.token, channels: channels) { [weak self] success in
                if success {
                    self?.backoffCounter?.resetCounter()
                    self?.onConnect?()
                    Logger.d("StreamingConnection: SSE connected")
                    Task { [weak self] in await self?.fetchCoordinator.refetchAll(delay: .none) }
                } else {
                    Logger.w("StreamingConnection: SSE connection failed")
                    self?.reportError(isRetryable: true)
                }
            }
        } catch {
            Logger.e("StreamingConnection: failed to get credential: \(error)")
            reportError(isRetryable: true)
        }
    }

    private func handleControl(_ notification: ThinControlNotification?) {
        guard let notification else { return }

        switch notification.controlType {
            case .streamingPaused:
                Logger.d("StreamingConnection: streaming paused by server")
            case .streamingResumed:
                Logger.d("StreamingConnection: streaming resumed by server")
            case .streamingDisabled:
                Logger.d("StreamingConnection: streaming disabled by server")
                stop()
            case .streamingReset:
                Logger.d("StreamingConnection: streaming reset by server")
                stop()
                Task { [weak self] in
                    guard let self else { return }
                    withLock(self.stateLock) { self.state = .started }
                    await connectSse()
                }
            case .unknown:
                break
        }
    }
}
