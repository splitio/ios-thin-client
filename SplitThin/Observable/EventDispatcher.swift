import Foundation
import Logging

protocol Observer: Sendable {
    func notify(event: ObservableEvent) throws
}

final class EventDispatcher: Observer, @unchecked Sendable {

    private var observers = [Observer]()
    private let lock = NSLock()

    func register(observer: Observer) {
        withLock(lock) {
            observers.append(observer)
        }
    }

    func notify(event: ObservableEvent) {
        let snapshot = withLock(lock) { observers }
        for observer in snapshot {
            do {
                try observer.notify(event: event)
            } catch {
                Logger.e("EventDispatcher: Observer failed for event \(event): \(error)")
            }
        }
    }
}
