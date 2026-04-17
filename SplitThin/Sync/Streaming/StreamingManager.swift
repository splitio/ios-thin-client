import Foundation
import Logging

protocol StreamingManager {
    func start()
    func stop()
    func pause()
    func resume()
    func stopAll()
}

final class DefaultStreamingManager: StreamingManager, @unchecked Sendable {

    private var connectionManager: StreamingConnectionManager?
    private let lock = NSLock()
    private let connectionManagerFactory: () -> StreamingConnectionManager

    init(connectionManagerFactory: @escaping () -> StreamingConnectionManager) {
        self.connectionManagerFactory = connectionManagerFactory
    }

    func start() {
        let mgr = withLock(lock) { () -> StreamingConnectionManager in
            if connectionManager == nil {
                connectionManager = connectionManagerFactory()
            }
            return connectionManager!
        }
        mgr.start()
    }

    func stop() {
        withLock(lock) { connectionManager }?.stop()
    }

    func pause() {
        withLock(lock) { connectionManager }?.pause()
    }

    func resume() {
        withLock(lock) { connectionManager }?.resume()
    }

    func stopAll() {
        let mgr = withLock(lock) {
            let m = connectionManager
            connectionManager = nil
            return m
        }
        mgr?.stop()
    }
}
