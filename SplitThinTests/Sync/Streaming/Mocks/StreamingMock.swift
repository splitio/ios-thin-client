import Foundation
@testable import SplitThin

final class StreamingMock: Streaming, @unchecked Sendable {
    var startCallCount = 0
    var stopCallCount = 0
    var pauseCallCount = 0
    var resumeCallCount = 0
    var handleNotificationCallCount = 0
    var lastNotification: ThinNotification?
    var pushDisabledHandler: (() -> Void)?

    func start() { startCallCount += 1 }
    func stop() async { stopCallCount += 1 }
    func pause() { pauseCallCount += 1 }
    func resume() { resumeCallCount += 1 }
    func handleNotification(_ notification: ThinNotification) {
        handleNotificationCallCount += 1
        lastNotification = notification
    }
    func setPushDisabledHandler(_ handler: @escaping () -> Void) {
        pushDisabledHandler = handler
    }
}
