//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

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
