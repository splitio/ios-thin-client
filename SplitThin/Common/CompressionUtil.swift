//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Compression

enum CompressionType: Int {
    case none = 0
    case gzip = 1
    case zlib = 2

    static func from(_ value: Int?) -> CompressionType {
        guard let value else { return .none }
        return CompressionType(rawValue: value) ?? .none
    }
}

enum CompressionError: Error {
    case couldNotDecompressData
    case couldNotDecompressZlib
    case couldNotDecompressGzip
    case headerSizeError
}

protocol CompressionUtil {
    func decompress(data: Data) throws -> Data
}

func decompressor(for type: CompressionType) -> CompressionUtil {
    switch type {
        case .gzip: Gzip()
        case .zlib: Zlib()
        case .none: CompressionNone()
    }
}

// MARK: - Implementations

struct Gzip: CompressionUtil {
    private let kGzipHeaderSize = 10

    func decompress(data: Data) throws -> Data {
        let headerSize = computeHeaderSize(data: data)
        guard headerSize > 0 else { throw CompressionError.headerSizeError }

        let deflatedData = data.dropFirst(headerSize)
        do {
            return try DeflateDecompressor.decompress(data: Data(deflatedData))
        } catch {
            throw CompressionError.couldNotDecompressGzip
        }
    }

    // Based on https://datatracker.ietf.org/doc/html/rfc1952
    private func computeHeaderSize(data: Data) -> Int {
        guard data.count >= kGzipHeaderSize,
              data[0] == 0x1f, data[1] == 0x8b, // ID1, ID2
              data[2] == 8 else { return -1 } // CM = deflate

        var headerSize = kGzipHeaderSize
        let flg = data[3]

        // FEXTRA — extra field
        if flg & (1 << 2) != 0 {
            headerSize += (Int(data[12]) | Int(data[13] & 0xff) << 8) + 4
        }
        // FNAME — file name (zero-terminated)
        if flg & (1 << 3) != 0 {
            if let end = Data(data[headerSize...]).firstIndex(of: 0) {
                headerSize += (end + 1)
            } else { return -1 }
        }
        // FCOMMENT — comment (zero-terminated)
        if flg & (1 << 4) != 0 {
            if let end = Data(data[headerSize...]).firstIndex(of: 0) {
                headerSize += (end + 1)
            } else { return -1 }
        }
        // FHCRC — header CRC
        if flg & (1 << 1) != 0 {
            headerSize += 2
        }
        return headerSize
    }
}

struct Zlib: CompressionUtil {
    private let kZlibHeaderSize = 2

    func decompress(data: Data) throws -> Data {
        let deflatedData = data.dropFirst(kZlibHeaderSize)
        do {
            return try DeflateDecompressor.decompress(data: Data(deflatedData))
        } catch {
            throw CompressionError.couldNotDecompressZlib
        }
    }
}

struct CompressionNone: CompressionUtil {
    func decompress(data: Data) throws -> Data { data }
}

// MARK: - Core deflate decompression

// Bitmap payloads can have compression ratios up to 1032:1
// https://zlib.net/zlib_tech.html
private enum DeflateDecompressor {
    private static let ratio = 1032

    static func decompress(data: Data) throws -> Data {
        let dstBufferSize = data.count * ratio
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: dstBufferSize)
        defer { dstBuffer.deallocate() }

        let srcBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { srcBuffer.deallocate() }
        data.copyBytes(to: srcBuffer, count: data.count)

        let decompressedSize = compression_decode_buffer(dstBuffer, dstBufferSize, srcBuffer, data.count, nil, COMPRESSION_ZLIB)
        guard decompressedSize > 0 else { throw CompressionError.couldNotDecompressData }

        return Data(bytes: dstBuffer, count: decompressedSize)
    }
}
