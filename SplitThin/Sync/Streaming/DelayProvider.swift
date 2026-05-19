//  Created by Gaston Thea
//  Copyright © 2026 Harness. All rights reserved

import Foundation

struct RefetchDelay {
    let intervalMs: Int64
    let seed: Int

    static let none = RefetchDelay(intervalMs: 0, seed: 0)
}

/// Computes a deterministic per-key delay in seconds within [0, intervalMs) using Murmur3Hash.
func computeKeyDelay(matchingKey: String, delay: RefetchDelay) -> TimeInterval {
    guard delay.intervalMs > 0 else { return 0 }

    let hash = Murmur3Hash.hashString(matchingKey, UInt32(truncatingIfNeeded: delay.seed))
    let bucket = Int64(bitPattern: UInt64(hash)) % delay.intervalMs
    let ms = bucket < 0 ? -bucket : bucket
    return Double(ms) / 1000.0
}
