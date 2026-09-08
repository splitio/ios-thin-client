//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
@testable import SplitThin

final class EventsConsentControllableMock: EventsConsentControllable, @unchecked Sendable {

    var enablePersistenceCalls = [Bool]()
    var clearInMemoryCallCount = 0

    /// Lets a test suspend inside `enablePersistence` to exercise actor reentrancy.
    var onEnablePersistence: (@Sendable (Bool) async -> Void)?

    var lastPersistenceValue: Bool? { enablePersistenceCalls.last }

    func enablePersistence(_ enable: Bool) async {
        enablePersistenceCalls.append(enable)
        await onEnablePersistence?(enable)
    }

    func clearInMemory() async {
        clearInMemoryCallCount += 1
    }
}
