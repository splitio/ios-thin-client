//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

protocol EventsValidator: Sendable {
    func validate(_ event: EventEntity) -> Bool
}

final class DefaultEventsValidator: EventsValidator {

    func validate(_ event: EventEntity) -> Bool {
        !event.eventType.trimmingCharacters(in: .whitespaces).isEmpty
            && !event.trafficType.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
