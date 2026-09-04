import Foundation

// Replica exacta de SplitThin/Common/Murmur3Hash.swift
enum Murmur3Hash {
    static let c1: UInt32 = 0xCC9E2D51
    static let c2: UInt32 = 0x1B873593
    static let r1: UInt32 = 15
    static let r2: UInt32 = 13
    static let m: UInt32 = 5
    static let n: UInt32 = 0xE6546B64

    static func hashString(_ s: String, _ seed: UInt32) -> UInt32 {
        hashBytesLittleEndian(Array(s.utf8), seed)
    }
    static func calcK(_ value: UInt32) -> UInt32 {
        var k = value
        k = k &* c1
        k = (k << r1) | (k >> (32 - r1))
        k = k &* c2
        return k
    }
    static func update2(_ hashIn: UInt32, _ value: UInt32) -> UInt32 {
        let k = calcK(value)
        var hash = hashIn
        hash = hash ^ k
        hash = (hash << r2) | (hash >> (32 - r2))
        hash = hash &* m &+ n
        return hash
    }
    static func finish(_ hashin: UInt32, byteCount: Int) -> UInt32 {
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
    static func hashBytesLittleEndian(_ bytes: [UInt8], _ seed: UInt32) -> UInt32 {
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
            hash ^= calcK(lastWord)
        }
        return finish(hash, byteCount: byteCount)
    }
}

// Parámetros tomados del push real: i=30000, s(seed)=0
let intervalMs: Int64 = 30000
let seed: UInt32 = 0
let minDelayMs: Int64 = 500

func delayMs(_ key: String) -> Int64 {
    guard intervalMs > minDelayMs else { return max(intervalMs, 0) }
    let hash = Murmur3Hash.hashString(key, seed)
    let bucket = Int64(bitPattern: UInt64(hash)) % (intervalMs - minDelayMs)
    return minDelayMs + (bucket < 0 ? -bucket : bucket)
}

// Busca una key que dé exactamente 5000ms (5s). delay=5000 => bucket=4500.
let targetMs: Int64 = 5000
for i in 0..<2_000_000 {
    let key = "demo-user-\(i)"
    if delayMs(key) == targetMs {
        print("key=\(key)  delay=\(Double(delayMs(key)) / 1000.0)s")
        break
    }
}
