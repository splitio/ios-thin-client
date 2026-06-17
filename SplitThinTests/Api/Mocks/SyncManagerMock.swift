import Foundation
@testable import SplitThin

final class SyncManagerMock: SyncManager, MobileSync, @unchecked Sendable {

    var startCallCount = 0
    var stopCallCount = 0
    var pauseCallCount = 0
    var resumeCallCount = 0
    var setTargetCallCount = 0
    var lastTargetSet: Target?

    func start() {
        startCallCount += 1
    }

    func stop() async {
        stopCallCount += 1
    }

    func setTarget(_ target: Target) {
        setTargetCallCount += 1
        lastTargetSet = target
    }

    func pause() {
        pauseCallCount += 1
    }

    func resume() {
        resumeCallCount += 1
    }
}
