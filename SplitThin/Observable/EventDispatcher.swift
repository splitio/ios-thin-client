//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol Observer: Sendable {
    func notify(event: ObservableEvent)
}

// This component is "CompositeObserver" in the spec
final class EventDispatcher: Observer, @unchecked Sendable {

    private var observers = [Observer]()
    private let lock = NSLock()

    func register(_ observer: Observer) {
        withLock(lock) {
            observers.append(observer)
        }
    }

    func unregisterAll() {
        withLock(lock) {
            observers.removeAll()
        }
    }

    func notify(event: ObservableEvent) {
        let snapshot = withLock(lock) { observers }
        for observer in snapshot {
            observer.notify(event: event)
        }
    }
}
