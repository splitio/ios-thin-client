//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

struct EventDTO: Sendable {
    let id: UUID
    let trafficType: String
    let eventType: String
    let value: Double?
    let properties: String?
    let timestamp: Double
}
