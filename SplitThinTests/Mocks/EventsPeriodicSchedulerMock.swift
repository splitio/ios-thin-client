//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
@testable import SplitThin

final class EventsPeriodicSchedulerMock: EventsPeriodicScheduler, @unchecked Sendable {

    var startCallCount = 0
    var stopCallCount = 0

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }
}
