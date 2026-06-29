//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

enum Murmur3Hash {

    private static let c1: UInt32 = 0xCC9E2D51
    private static let c2: UInt32 = 0x1B873593
    private static let r1: UInt32 = 15
    private static let r2: UInt32 = 13
    private static let m: UInt32 = 5
    private static let n: UInt32 = 0xE6546B64

    static func attributesHash(for attributes: [String: Any]?) -> String {
        guard let attributes, !attributes.isEmpty else { return "" }
        guard let data = try? JSONSerialization.data(withJSONObject: attributes, options: .sortedKeys),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return String(hashString(json, 0))
    }

    static func hashString(_ s: String, _ seed: UInt32) -> UInt32 {
        let bytes = Array(s.utf8)
        return hashBytesLittleEndian(bytes, seed)
    }

    private static func calcK(_ value: UInt32) -> UInt32 {
        var k = value
        k = k &* c1
        k = (k << r1) | (k >> (32 - r1))
        k = k &* c2
        return k
    }

    private static func update2(_ hashIn: UInt32, _ value: UInt32) -> UInt32 {
        let k = calcK(value)
        var hash = hashIn
        hash = hash ^ k
        hash = (hash << r2) | (hash >> (32 - r2))
        hash = hash &* m &+ n
        return hash
    }

    private static func finish(_ hashin: UInt32, byteCount: Int) -> UInt32 {
        let bc = UInt32(truncatingIfNeeded: byteCount)
        var hash = hashin
        hash ^= bc
        hash ^= (hash >> 16)
        hash = hash &* 0x85EBCA6B
        hash ^= (hash >> 13)
        hash = hash &* 0xC2B2AE35
        hash ^= (hash >> 16)
        return hash
    }

    private static func hashBytesLittleEndian(_ bytes: [UInt8], _ seed: UInt32) -> UInt32 {
        let byteCount = bytes.count
        var hash = seed
        for i in stride(from: 0, to: byteCount - 3, by: 4) {
            var word = UInt32(bytes[i])
            word |= UInt32(bytes[i + 1]) << 8
            word |= UInt32(bytes[i + 2]) << 16
            word |= UInt32(bytes[i + 3]) << 24
            hash = update2(hash, word)
        }
        let remaining = byteCount & 3
        if remaining != 0 {
            var lastWord = UInt32(0)
            for r in 0 ..< remaining {
                lastWord |= UInt32(bytes[byteCount - 1 - r]) << (8 * (remaining - 1 - r))
            }
            let k = calcK(lastWord)
            hash ^= k
        }
        return finish(hash, byteCount: byteCount)
    }
}
