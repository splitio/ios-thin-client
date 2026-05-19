//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Tracker
@testable import SplitThin

final class TrackerMock: Tracker, @unchecked Sendable {

    var isTrackingEnabled: Bool = true
    var trackCalls = [(eventType: String, trafficType: String?, value: Double?, properties: [String: Any]?, matchingKey: String)]()
    var trackResult = true

    func track(eventType: String, trafficType: String?, value: Double?, properties: [String: Any]?, matchingKey: String, isSdkReady: Bool) -> Bool {
        trackCalls.append((eventType, trafficType, value, properties, matchingKey))
        return trackResult
    }
}
