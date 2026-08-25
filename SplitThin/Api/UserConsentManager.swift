//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

/// The per-client set of components whose behavior depends on user consent.
///
/// Consent is factory-wide, but the thin client creates event components per client,
/// so the manager fans a status change out to every registered bundle.
struct ConsentControllableBundle: Sendable {
    let storage: EventsConsentControllable
    let tracker: EventsTracker
    let scheduler: EventsPeriodicScheduler
    let coordinator: EventSubmissionCoordinator
}

protocol UserConsentManager: Sendable {
    /// Applies a new factory-wide consent status to every registered bundle.
    func set(_ status: UserConsent) async
    /// Registers a client's components and immediately applies the current status.
    func register(_ bundle: ConsentControllableBundle) async
    /// Current factory-wide consent status.
    func getStatus() async -> UserConsent
    /// Discards every in-memory buffer (used on factory destroy).
    func clearPending() async
}

/// Factory-wide user consent manager. Mirrors `DefaultUserConsentManager` from the full
/// SDK (`ios-client`) on two axes:
/// - tracking: enabled unless `declined`
/// - persistence: enabled only when `granted`
/// plus submission (recorders), which run only when `granted`.
///
/// Implemented as an actor so status changes and bundle registration are serialized,
/// keeping the grant transition (flush-then-enable-submission) race-free.
actor DefaultUserConsentManager: UserConsentManager {

    private var currentStatus: UserConsent
    private var bundles = [ConsentControllableBundle]()

    init(initialStatus: UserConsent) {
        self.currentStatus = initialStatus
    }

    func getStatus() -> UserConsent {
        currentStatus
    }

    func register(_ bundle: ConsentControllableBundle) async {
        bundles.append(bundle)
        await apply(currentStatus, to: bundle)
    }

    func set(_ status: UserConsent) async {
        guard status != currentStatus else { return }
        currentStatus = status
        for bundle in bundles {
            await apply(status, to: bundle)
        }
        Logger.d("UserConsent set to \(status)")
    }

    func clearPending() async {
        for bundle in bundles {
            await bundle.storage.clearInMemory()
        }
    }

    // MARK: - Private

    private func apply(_ status: UserConsent, to bundle: ConsentControllableBundle) async {
        // Tracking is allowed unless the user declined.
        bundle.tracker.setTrackingEnabled(status != .declined)

        if status == .granted {
            // Persist (and flush the in-memory buffer) BEFORE enabling submission, so a
            // recorder can never run against a half-drained queue.
            await bundle.storage.enablePersistence(true)
            bundle.coordinator.setSubmissionEnabled(true)
            bundle.scheduler.start()
        } else {
            // Stop submitting first, then stop persisting.
            bundle.scheduler.stop()
            bundle.coordinator.setSubmissionEnabled(false)
            await bundle.storage.enablePersistence(false)
            // Declined discards anything buffered while consent was unknown.
            if status == .declined {
                await bundle.storage.clearInMemory()
            }
        }
    }
}
