import Foundation
@testable import SplitThin

final class PayloadDecoderMock: PayloadDecoder, @unchecked Sendable {

    var bytesResult: Data = Data()
    var stringResult: String = ""
    var keyListResult: KeyList = KeyList(added: [], removed: [])
    var bitmapKeys: Set<UInt64> = []
    var errorToThrow: Error?

    private(set) var decodeAsBytesCalls = 0
    private(set) var decodeAsStringCalls = 0

    func decodeAsBytes(payload: String, compressionType: CompressionType) throws -> Data {
        decodeAsBytesCalls += 1
        if let error = errorToThrow { throw error }
        return bytesResult
    }

    func decodeAsString(payload: String, compressionType: CompressionType) throws -> String {
        decodeAsStringCalls += 1
        if let error = errorToThrow { throw error }
        return stringResult
    }

    func hashKey(_ key: String) -> UInt64 {
        Murmur64x128.hashKey(key)
    }

    func isKeyInBitmap(keyMap: Data, hashedKey: UInt64) -> Bool {
        bitmapKeys.contains(hashedKey)
    }

    func parseKeyList(jsonString: String) throws -> KeyList {
        if let error = errorToThrow { throw error }
        return keyListResult
    }
}
