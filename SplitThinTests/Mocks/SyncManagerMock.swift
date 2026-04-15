import Foundation
@testable import SplitThin

final class SyncManagerMock: SyncManager, @unchecked Sendable {

    var startCallCount = 0
    var stopCallCount = 0
    var pauseCallCount = 0
    var resumeCallCount = 0

    func start() {
        startCallCount += 1
    }

    func stop() async {
        stopCallCount += 1
    }

    func pause() {
        pauseCallCount += 1
    }

    func resume() {
        resumeCallCount += 1
    }
}
