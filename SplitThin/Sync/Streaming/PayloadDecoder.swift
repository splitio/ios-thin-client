//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

enum PayloadDecodingError: Error {
    case base64DecodingFailed
}

struct KeyList {
    let added: Set<UInt64>
    let removed: Set<UInt64>
}

protocol PayloadDecoder {
    func decodeAsBytes(payload: String, compressionType: CompressionType) throws -> Data
    func decodeAsString(payload: String, compressionType: CompressionType) throws -> String
    func hashKey(_ key: String) -> UInt64
    func isKeyInBitmap(keyMap: Data, hashedKey: UInt64) -> Bool
    func parseKeyList(jsonString: String) throws -> KeyList
}

struct DefaultPayloadDecoder: PayloadDecoder {

    private let kBitsPerByte = 8

    func decodeAsBytes(payload: String, compressionType: CompressionType) throws -> Data {
        guard let decoded = decodeBase64URLSafe(payload) else {
            throw PayloadDecodingError.base64DecodingFailed
        }
        return try decompressor(for: compressionType).decompress(data: decoded)
    }

    func decodeAsString(payload: String, compressionType: CompressionType) throws -> String {
        let data = try decodeAsBytes(payload: payload, compressionType: compressionType)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func hashKey(_ key: String) -> UInt64 {
        Murmur64x128.hashKey(key)
    }

    func isKeyInBitmap(keyMap: Data, hashedKey: UInt64) -> Bool {
        let totalBits = keyMap.count * kBitsPerByte
        guard totalBits > 0 else { return false }

        let index = Int(hashedKey % UInt64(totalBits))
        let byteIndex = index / kBitsPerByte
        let bitOffset = UInt8(index % kBitsPerByte)

        guard byteIndex < keyMap.count else { return false }

        return (keyMap[byteIndex] & (1 << bitOffset)) != 0
    }

    func parseKeyList(jsonString: String) throws -> KeyList {
        guard let data = jsonString.data(using: .utf8) else { throw JsonError.invalidData }
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = jsonObject as? [String: Any] else { throw JsonError.parsingFailed }

        let added = (dict["a"] as? [UInt64]).map(Set.init) ?? []
        let removed = (dict["r"] as? [UInt64]).map(Set.init) ?? []
        return KeyList(added: added, removed: removed)
    }

    // MARK: - Private

    /// Decodes a URL-safe base64 string (handles `-` → `+`, `_` → `/`, missing padding).
    private func decodeBase64URLSafe(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let mod4 = base64.count % 4
        if mod4 > 0 {
            base64 += String(repeating: "=", count: 4 - mod4)
        }
        return Data(base64Encoded: base64)
    }
}
