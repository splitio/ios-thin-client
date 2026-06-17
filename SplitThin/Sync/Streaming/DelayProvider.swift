//  Created by Gaston Thea
//  Copyright © 2026 Harness. All rights reserved

import Foundation

struct RefetchDelay {
    let intervalMs: Int64
    let seed: Int

    static let none = RefetchDelay(intervalMs: 0, seed: 0)
    static let minDelayMs: Int64 = 500

    /// Computes a deterministic per-key delay in seconds within [minDelayMs, intervalMs) using Murmur3Hash.
    func delay(forKey matchingKey: String) -> TimeInterval {
        guard intervalMs > Self.minDelayMs else {
            return Double(max(intervalMs, 0)) / 1000.0
        }

        let hash = Murmur3Hash.hashString(matchingKey, UInt32(truncatingIfNeeded: seed))
        let bucket = Int64(bitPattern: UInt64(hash)) % (intervalMs - Self.minDelayMs)
        let ms = Self.minDelayMs + (bucket < 0 ? -bucket : bucket)
        return Double(ms) / 1000.0
    }
}
