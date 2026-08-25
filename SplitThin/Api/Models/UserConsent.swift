//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

/// - `unknown`: events are tracked in memory but neither persisted nor submitted
/// - `granted`: events are tracked, persisted and submitted normally.
/// - `declined`: events are not tracked.
public enum UserConsent: Int, Sendable {
    case unknown = 1
    case granted = 2
    case declined = 3
}
