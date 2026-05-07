//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

protocol EventSerializer: Sendable {
    func serialize(_ events: [EventEntity]) throws -> Data
}

final class DefaultEventSerializer: EventSerializer {

    func serialize(_ events: [EventEntity]) throws -> Data {
        try JSONSerialization.data(withJSONObject: events.map { $0.toJsonObject() })
    }
}
