import Foundation
@testable import SplitThin

final class SplitEventsManagerMock: SplitEventsManager, @unchecked Sendable {

    var addedListeners = [SplitEventListener]()
    var removedListeners = [SplitEventListener]()
    var notifiedEvents = [SplitInternalEvent]()

    var startCallCount = 0
    var stopCallCount = 0
    var isReadyResult = false

    func addListener(_ listener: SplitEventListener) {
        addedListeners.append(listener)
    }

    func removeListener(_ listener: SplitEventListener) {
        removedListeners.append(listener)
    }

    func notifyInternalEvent(_ event: SplitInternalEvent) {
        notifiedEvents.append(event)
    }

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func isReady() -> Bool {
        isReadyResult
    }
}
