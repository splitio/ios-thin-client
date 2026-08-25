//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

/// Consent axis controlling whether tracked events are persisted.
protocol EventsConsentControllable: Sendable {
    /// Enables/disables persistence. When enabling, buffered in-memory events are
    /// flushed to the persistent storage. When disabling, new events accumulate in memory.
    func enablePersistence(_ enable: Bool) async
    /// Discards the in-memory buffer (used on decline/destroy while not granted).
    func clearInMemory() async
}

/// Wraps a persistent events storage and adds an in-memory buffer whose target is
/// decided per write by the `persistenceEnabled` flag. Mirrors `MainEventsStorage`
/// from the full SDK (`ios-client`): while consent is not granted, events are held in
/// memory (not persisted, not submitted); on grant, the buffer is flushed to the
/// persistent store.
///
/// The `persistenceEnabled` flag and the buffer share a single lock so that a
/// transition (flush + flag flip) is atomic with respect to concurrent `add` calls:
/// an event either lands in the buffer that is about to be drained, or goes straight
/// to the persistent store. There is no third place for it to get lost.
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
        // Flip the flag and drain the buffer under the same lock so no concurrent
        // `add` can slip an event into a buffer that will no longer be drained.
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

    func add(_ events: [EventEntity]) async {
        let persist = withLock(lock) {
            if persistenceEnabled { return true }
            buffer.append(contentsOf: events)
            return false
        }

        if persist {
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

    // Reads only reflect the persistent store. While consent is not granted, submission
    // is stopped, so these are not consulted for the in-memory buffer.
    func getBatch(size: Int) async -> [EventEntity] {
        await persistentStorage.getBatch(size: size)
    }

    func count() async -> Int {
        await persistentStorage.count()
    }
}
