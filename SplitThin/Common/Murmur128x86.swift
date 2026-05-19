//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

/// MurmurHash3 x86_128 — 128-bit hash using 32-bit arithmetic.
/// Ported from the reference C++ implementation by Austin Appleby.
enum Murmur128x86 {

    private static let c1: UInt32 = 0x239b961b
    private static let c2: UInt32 = 0xab0e9789
    private static let c3: UInt32 = 0x38b34ae5
    private static let c4: UInt32 = 0xa1e38b93

    /// Hashes UTF-8 bytes of `string` with the given `seed` and returns the first
    /// 64 bits (h1 ++ h2) as big-endian `Data` (8 bytes).
    static func hashToData(_ string: String, seed: UInt32 = 0) -> Data {
        let h = hash(data: Array(string.utf8), seed: seed)
        var result = Data(count: 8)
        result[0] = UInt8((h[0] >> 24) & 0xFF)
        result[1] = UInt8((h[0] >> 16) & 0xFF)
        result[2] = UInt8((h[0] >> 8) & 0xFF)
        result[3] = UInt8(h[0] & 0xFF)
        result[4] = UInt8((h[1] >> 24) & 0xFF)
        result[5] = UInt8((h[1] >> 16) & 0xFF)
        result[6] = UInt8((h[1] >> 8) & 0xFF)
        result[7] = UInt8(h[1] & 0xFF)
        return result
    }

    // MARK: - Core

    static func hash(data: [UInt8], seed: UInt32) -> [UInt32] {
        let len = data.count
        let nblocks = len / 16
        var h1 = seed, h2 = seed, h3 = seed, h4 = seed

        for i in 0..<nblocks {
            var k1 = getBlock32(data, i * 16)
            var k2 = getBlock32(data, i * 16 + 4)
            var k3 = getBlock32(data, i * 16 + 8)
            var k4 = getBlock32(data, i * 16 + 12)

            k1 &*= c1; k1 = rotl32(k1, 15); k1 &*= c2; h1 ^= k1
            h1 = rotl32(h1, 19); h1 &+= h2; h1 = h1 &* 5 &+ 0x561ccd1b

            k2 &*= c2; k2 = rotl32(k2, 16); k2 &*= c3; h2 ^= k2
            h2 = rotl32(h2, 17); h2 &+= h3; h2 = h2 &* 5 &+ 0x0bcaa747

            k3 &*= c3; k3 = rotl32(k3, 17); k3 &*= c4; h3 ^= k3
            h3 = rotl32(h3, 15); h3 &+= h4; h3 = h3 &* 5 &+ 0x96cd1c35

            k4 &*= c4; k4 = rotl32(k4, 18); k4 &*= c1; h4 ^= k4
            h4 = rotl32(h4, 13); h4 &+= h1; h4 = h4 &* 5 &+ 0x32ac3b17
        }

        processTail(data: data, nblocks: nblocks, h1: &h1, h2: &h2, h3: &h3, h4: &h4)
        return finalize(len: len, h1: &h1, h2: &h2, h3: &h3, h4: &h4)
    }

    // MARK: - Private

    private static func rotl32(_ x: UInt32, _ r: UInt32) -> UInt32 {
        (x << r) | (x >> (32 - r))
    }

    private static func fmix32(_ h: UInt32) -> UInt32 {
        var h = h
        h ^= h >> 16; h &*= 0x85ebca6b
        h ^= h >> 13; h &*= 0xc2b2ae35
        h ^= h >> 16
        return h
    }

    private static func getBlock32(_ data: [UInt8], _ index: Int) -> UInt32 {
        UInt32(data[index]) | UInt32(data[index + 1]) << 8 | UInt32(data[index + 2]) << 16 | UInt32(data[index + 3]) << 24
    }

    private static func processTail(data: [UInt8], nblocks: Int, h1: inout UInt32, h2: inout UInt32, h3: inout UInt32, h4: inout UInt32) {
        let tail = nblocks * 16
        var k1: UInt32 = 0, k2: UInt32 = 0, k3: UInt32 = 0, k4: UInt32 = 0

        switch data.count & 15 {
            case 15: k4 ^= UInt32(data[tail + 14]) << 16; fallthrough
            case 14: k4 ^= UInt32(data[tail + 13]) << 8; fallthrough
            case 13:
                k4 ^= UInt32(data[tail + 12])
                k4 &*= c4; k4 = rotl32(k4, 18); k4 &*= c1; h4 ^= k4
                fallthrough
            case 12: k3 ^= UInt32(data[tail + 11]) << 24; fallthrough
            case 11: k3 ^= UInt32(data[tail + 10]) << 16; fallthrough
            case 10: k3 ^= UInt32(data[tail + 9]) << 8; fallthrough
            case 9:
                k3 ^= UInt32(data[tail + 8])
                k3 &*= c3; k3 = rotl32(k3, 17); k3 &*= c4; h3 ^= k3
                fallthrough
            case 8: k2 ^= UInt32(data[tail + 7]) << 24; fallthrough
            case 7: k2 ^= UInt32(data[tail + 6]) << 16; fallthrough
            case 6: k2 ^= UInt32(data[tail + 5]) << 8; fallthrough
            case 5:
                k2 ^= UInt32(data[tail + 4])
                k2 &*= c2; k2 = rotl32(k2, 16); k2 &*= c3; h2 ^= k2
                fallthrough
            case 4: k1 ^= UInt32(data[tail + 3]) << 24; fallthrough
            case 3: k1 ^= UInt32(data[tail + 2]) << 16; fallthrough
            case 2: k1 ^= UInt32(data[tail + 1]) << 8; fallthrough
            case 1:
                k1 ^= UInt32(data[tail])
                k1 &*= c1; k1 = rotl32(k1, 15); k1 &*= c2; h1 ^= k1
            default: break
        }
    }

    private static func finalize(len: Int, h1: inout UInt32, h2: inout UInt32, h3: inout UInt32, h4: inout UInt32) -> [UInt32] {
        let l = UInt32(len)
        h1 ^= l; h2 ^= l; h3 ^= l; h4 ^= l

        h1 &+= h2; h1 &+= h3; h1 &+= h4
        h2 &+= h1; h3 &+= h1; h4 &+= h1

        h1 = fmix32(h1); h2 = fmix32(h2); h3 = fmix32(h3); h4 = fmix32(h4)

        h1 &+= h2; h1 &+= h3; h1 &+= h4
        h2 &+= h1; h3 &+= h1; h4 &+= h1

        return [h1, h2, h3, h4]
    }
}
