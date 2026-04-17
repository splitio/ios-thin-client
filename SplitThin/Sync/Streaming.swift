import Foundation

protocol Streaming: Sendable {
    func start() async
    func stop() async
    func pause()
    func resume()
}

final class DefaultStreaming: Streaming, @unchecked Sendable {

    private let streamingManager: StreamingManager

    init(streamingManager: StreamingManager) {
        self.streamingManager = streamingManager
    }

    func start() async {
        streamingManager.start()
    }

    func stop() async {
        streamingManager.stop()
    }

    func pause() {
        streamingManager.pause()
    }

    func resume() {
        streamingManager.resume()
    }
}
