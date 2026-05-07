//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
@testable import SplitThin

final class EventsTrackerMock: EventsTracker, @unchecked Sendable {

    var trackedEvents = [EventEntity]()
    var flushCallCount = 0

    func track(_ event: EventEntity) async {
        trackedEvents.append(event)
    }

    func flush() async {
        flushCallCount += 1
    }
}
