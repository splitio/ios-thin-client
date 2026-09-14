//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Http

/// Bridges the `Http` module's pinning notifications to the customer-provided closures
/// configured in ``CertificatePinningConfig``. Unlike the full SDK, it invokes the
/// handlers directly instead of routing them through a notification center.
struct ThinPinningNotificationHandler: HttpNotificationHandler {
    private let failureHandler: CertificatePinningFailureHandler?
    private let statusHandler: CertificatePinningStatusHandler?

    init(failureHandler: CertificatePinningFailureHandler?, statusHandler: CertificatePinningStatusHandler?) {
        self.failureHandler = failureHandler
        self.statusHandler = statusHandler
    }

    // The Http layer calls this without a reason. We deliberately don't drive the public
    // failure handler from here: notifyPinningStatus(.failed) fires for the same set of hard
    // failures and carries the reason, so we surface failures from there instead.
    func notifyPinningFailure(host: String) {}

    func notifyPinningStatus(_ status: CertificatePinningCompleteStatus) {
        if status.status == .failed {
            failureHandler?(status.host, status.reason)
        }
        statusHandler?(status.host, status.status, status.reason)
    }
}
