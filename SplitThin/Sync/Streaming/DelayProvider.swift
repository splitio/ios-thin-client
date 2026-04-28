//  Created by Gaston Thea
//  Copyright © 2026 Harness. All rights reserved

import Foundation

typealias DelayProvider = (EvaluationUpdateNotification?, String) -> TimeInterval

func buildDelayProvider() -> DelayProvider {
    return { notification, key in
        guard let intervalMs = notification?.updateIntervalMs,
              let seed = notification?.algorithmSeed else {
            return 0
        }
        let hash = Murmur3Hash.hashString(key, UInt32(truncatingIfNeeded: seed))
        let bucket = Int64(bitPattern: UInt64(hash)) % intervalMs
        let ms = bucket < 0 ? -bucket : bucket
        return Double(ms) / 1000.0
    }
}
