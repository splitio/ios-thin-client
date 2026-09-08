//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

/// Consent axis controlling whether tracked events are persisted.
protocol EventsConsentControllable: Sendable {
    /// When enabling, buffered in-memory events are flushed to the persistent storage. 
    /// When disabling, new events accumulate in memory.
    func enablePersistence(_ enable: Bool) async

    func clearInMemory() async
}

/// Wraps a persistent events storage and adds an in-memory buffer
final class UserConsentTemporaryStorage: EventsReadStorage, EventsWriteStorage, EventsConsentControllable, @unchecked Sendable {

    private static let maxInMemoryEvents = 10_000

    private let persistentStorage: EventsReadStorage & EventsWriteStorage
    private let lock = NSLock()
    private var persistenceEnabled: Bool
    private var buffer = [EventEntity]()

    init(persistentStorage: EventsReadStorage & EventsWriteStorage, persistenceEnabled: Bool) {
        self.persistentStorage = persistentStorage
        self.persistenceEnabled = persistenceEnabled
    }

    // MARK: - EventsConsentControllable

    func enablePersistence(_ enable: Bool) async {
        let pending: [EventEntity] = withLock(lock) {
            persistenceEnabled = enable
            guard enable else { return [] }
            let drained = buffer
            buffer.removeAll()
            return drained
        }

        if !pending.isEmpty {
            Logger.v("UserConsentTemporaryStorage: flushing \(pending.count) buffered events to persistent storage")
            await persistentStorage.add(pending)
        }
        Logger.d("UserConsentTemporaryStorage: persistence \(enable ? "enabled" : "disabled")")
    }

    func clearInMemory() async {
        withLock(lock) { buffer.removeAll() }
        Logger.d("UserConsentTemporaryStorage: in-memory buffer cleared")
    }

    // MARK: - EventsWriteStorage

    func add(_ event: EventEntity) async {
        await add([event])
    }

    // persist ? saveToDisk : saveInMemory
    func add(_ events: [EventEntity]) async {
        let (shouldPersist, dropped) = withLock(lock) { () -> (Bool, Int) in
            if persistenceEnabled { return (true, 0) }
            buffer.append(contentsOf: events)
            let overflow = max(0, buffer.count - Self.maxInMemoryEvents)
            if overflow > 0 { buffer.removeFirst(overflow) }
            return (false, overflow)
        }

        if shouldPersist {
            await persistentStorage.add(events)
        } else if dropped > 0 {
            Logger.w("UserConsentTemporaryStorage: in-memory buffer full (\(Self.maxInMemoryEvents)); dropped \(dropped) oldest tracked event(s) that will not be submitted")
        }
    }

    func remove(_ events: [EventEntity]) async {
        await persistentStorage.remove(events)
    }

    func clear() async {
        withLock(lock) { buffer.removeAll() }
        await persistentStorage.clear()
    }

    // MARK: - EventsReadStorage

    func getBatch(size: Int) async -> [EventEntity] {
        await persistentStorage.getBatch(size: size)
    }

    func count() async -> Int {
        await persistentStorage.count()
    }
}
