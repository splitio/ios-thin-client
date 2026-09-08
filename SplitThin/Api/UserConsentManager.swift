//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol UserConsentManager: Sendable {
    func start() async
    func set(_ status: UserConsent) async
    func clearPending() async
}

/// Factory-wide user consent manager. 
/// - tracking: enabled unless `declined`
/// - persistence: enabled only when `granted`
actor DefaultUserConsentManager: UserConsentManager {

    private var currentStatus: UserConsent
    private let storage: EventsConsentControllable
    private let eventsTracker: EventsTracker
    private let eventsScheduler: EventsPeriodicScheduler
    private let eventsCoordinator: EventSubmissionCoordinator

    init(initialStatus: UserConsent, storage: EventsConsentControllable, tracker: EventsTracker, scheduler: EventsPeriodicScheduler, coordinator: EventSubmissionCoordinator) {
        self.currentStatus = initialStatus
        self.storage = storage
        self.eventsTracker = tracker
        self.eventsScheduler = scheduler
        self.eventsCoordinator = coordinator
    }

    func start() async {
        await apply(currentStatus)
    }

    func set(_ status: UserConsent) async {
        guard status != currentStatus else { return }
        currentStatus = status
        await apply(status)
        Logger.d("UserConsent set to \(status)")
    }

    func clearPending() async {
        await storage.clearInMemory()
    }

    // MARK: - Private

    private func apply(_ status: UserConsent) async {

        // Enable/Disable events tracking
        eventsTracker.setTrackingEnabled(status != .declined)

        // Enable/Disable persistence (local & remote)
        if status == .granted {
            await storage.enablePersistence(true)

            guard status == currentStatus else { return } // Re-checking the status after each suspension
            eventsCoordinator.setSubmissionEnabled(true)
            eventsScheduler.start()
        } else {
            eventsScheduler.stop()
            eventsCoordinator.setSubmissionEnabled(false)
            await storage.enablePersistence(false)

            guard status == currentStatus else { return } // Re-checking the status after each suspension
            if status == .declined { // Delete everything recorded until Declined
                await storage.clearInMemory()
            }
        }
    }
}
