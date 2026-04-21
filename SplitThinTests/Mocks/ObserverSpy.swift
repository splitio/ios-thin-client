import Foundation
@testable import SplitThin

final class ObserverSpy: Observer, @unchecked Sendable {

    private let lock = NSLock()
    private var _notifiedEvents = [ObservableEvent]()

    var notifiedEvents: [ObservableEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _notifiedEvents
    }

    var eventNames: [String] {
        notifiedEvents.map { $0.name }
    }

    func notify(event: ObservableEvent) {
        lock.lock()
        _notifiedEvents.append(event)
        lock.unlock()
    }
}

// This is used to test observed events.
// Since mirroring is very expensive on runtime, we put it here so it can't be used in prod.
extension ObservableEvent {
    var name: String {
        Mirror(reflecting: self).children.first?.label ?? String(describing: self)
    }
}