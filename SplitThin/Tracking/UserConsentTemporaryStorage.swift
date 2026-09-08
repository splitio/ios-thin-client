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
        let shouldPersist = withLock(lock) { () -> Bool in
            if persistenceEnabled {
                return true
            } else {
                buffer.append(contentsOf: events)
                return false
            }
        }

        if shouldPersist {
            await persistentStorage.add(events)
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
