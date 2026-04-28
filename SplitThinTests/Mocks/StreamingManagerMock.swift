import Foundation
@testable import SplitThin

final class StreamingManagerMock: StreamingManager, @unchecked Sendable {
    var startCallCount = 0
    var stopCallCount = 0
    var pauseCallCount = 0
    var resumeCallCount = 0
    var stopAllCallCount = 0

    func start() { startCallCount += 1 }
    func stop() { stopCallCount += 1 }
    func pause() { pauseCallCount += 1 }
    func resume() { resumeCallCount += 1 }
    func stopAll() { stopAllCallCount += 1 }
}
