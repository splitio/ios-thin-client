import Foundation
import Logging
import Http
import Streaming
import BackoffCounter

protocol StreamingConnectionManager {
    func start()
    func stop()
    func pause()
    func resume()
    func handleNotification(_ notification: ThinNotification)
}

final class DefaultStreamingConnectionManager: StreamingConnectionManager, SseHandler, @unchecked Sendable {

    private enum State { case stopped, started, paused }

    private let target: Target
    private let authProvider: AuthProvider?
    private let streamingEndpoint: URL?
    private let httpClient: HttpClient?
    private let fetchCoordinator: EvaluationFetchCoordinator
    private let notificationParser: ThinNotificationParser
    private let jwtParser: SseJwtParser?
    private let backoffCounter: BackoffCounter?
    private let onConnect: (() -> Void)?
    private let onPushDisabled: (() -> Void)?

    private var state: State = .stopped
    private let stateLock = NSLock()
    private var activeConnectionHandler: SseConnectionHandler?

    // Convenience init for testing (no network required)
    init(target: Target,
         fetchCoordinator: EvaluationFetchCoordinator,
         notificationParser: ThinNotificationParser,
         onPushDisabled: (() -> Void)? = nil) {
        self.target = target
        self.authProvider = nil
        self.streamingEndpoint = nil
        self.httpClient = nil
        self.fetchCoordinator = fetchCoordinator
        self.notificationParser = notificationParser
        self.jwtParser = nil
        self.backoffCounter = nil
        self.onConnect = nil
        self.onPushDisabled = onPushDisabled
    }

    // Full init for production use
    init(target: Target,
         authProvider: AuthProvider,
         streamingEndpoint: URL,
         httpClient: HttpClient,
         fetchCoordinator: EvaluationFetchCoordinator,
         notificationParser: ThinNotificationParser,
         jwtParser: SseJwtParser,
         backoffCounter: BackoffCounter,
         onConnect: (() -> Void)? = nil) {
        self.target = target
        self.authProvider = authProvider
        self.streamingEndpoint = streamingEndpoint
        self.httpClient = httpClient
        self.fetchCoordinator = fetchCoordinator
        self.notificationParser = notificationParser
        self.jwtParser = jwtParser
        self.backoffCounter = backoffCounter
        self.onConnect = onConnect
        self.onPushDisabled = nil
    }

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
        withLock(stateLock) { state = .stopped }
        activeConnectionHandler?.disconnect()
    }

    func pause() {
        withLock(stateLock) { state = .paused }
        activeConnectionHandler?.disconnect()
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

    func handleNotification(_ notification: ThinNotification) {
        switch notification.type {
            case .evaluationUpdate:
                let evalNotification = notification as? EvaluationUpdateNotification
                Task { [weak self] in
                    guard let self else { return }
                    await self.fetchCoordinator.refetchAll(notification: evalNotification)
                }
            case .control:
                handleControl(notification as? ThinControlNotification)
            case .occupancy:
                if let occupancy = notification as? ThinOccupancyNotification, occupancy.publishers == 0 {
                    onPushDisabled?()
                }
            case .error:
                if let error = notification as? ThinStreamingError {
                    reportError(isRetryable: error.isRetryable)
                }
        }
    }

    // MARK: - SseHandler

    func isConnectionConfirmed(message: [String: String]) -> Bool {
        return message["id"] != nil || message["data"] != nil
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
        Logger.w("StreamingConnectionManager: SSE error, retryable=\(isRetryable)")
        guard isRetryable else {
            withLock(stateLock) { state = .stopped }
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let delay = backoffCounter?.getNextRetryTime() ?? 1
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await connectSse()
        }
    }

    // MARK: - Private

    private func connectSse() async {
        guard let authProvider, let jwtParser, let streamingEndpoint, let httpClient else { return }
        guard !withLock(stateLock, { state == .stopped }) else { return }

        do {
            let credential = try await authProvider.getCredential(for: target.matchingKey)
            guard credential.pushEnabled else {
                Logger.d("StreamingConnectionManager: push not enabled")
                return
            }
            guard let channels = jwtParser.extractChannels(from: credential.token), !channels.isEmpty else {
                Logger.w("StreamingConnectionManager: no channels in JWT")
                return
            }

            let kAblySplitSdkClientKeyLength = 4
            
            let endpoint = Endpoint.builder(baseUrl: streamingEndpoint).set(method: .get).add(headers:
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
                    Logger.d("StreamingConnectionManager: SSE connected")
                    Task { [weak self] in await self?.fetchCoordinator.refetchAll(notification: nil) }
                } else {
                    Logger.w("StreamingConnectionManager: SSE connection failed")
                    self?.reportError(isRetryable: true)
                }
            }
        } catch {
            Logger.e("StreamingConnectionManager: failed to get credential: \(error)")
            reportError(isRetryable: true)
        }
    }

    private func handleControl(_ notification: ThinControlNotification?) {
        guard let notification else { return }
        switch notification.controlType {
        case .streamingPaused:
            Logger.d("StreamingConnectionManager: streaming paused by server")
        case .streamingResumed:
            Logger.d("StreamingConnectionManager: streaming resumed by server")
        case .streamingDisabled:
            Logger.d("StreamingConnectionManager: streaming disabled by server")
            stop()
        case .streamingReset:
            Logger.d("StreamingConnectionManager: streaming reset by server")
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
