import XCTest
@testable import SplitThin

final class PayloadDecoderTest: XCTestCase {

    private var decoder: DefaultPayloadDecoder!

    // Gzip-compressed bounded payload from ios-client test data.
    // Contains a bitmap where these 10 UUID keys all have their bit set.
    private let boundedPayloadGzip = "H4sIAAAAAAAA/2IYBfgAx0A7YBTgB4wD7YABAAID7QC6g5EYy8MEMA20A+gMFAbaAYMZDPXqlGWgHTAKRsEoGAWjgCzQQFjJkKqiiPAPAQAIAAD//5L7VQwAEAAA"

    // Zlib-compressed bounded payload (same bitmap data)
    private let boundedPayloadZlib = "eJxiGAX4AMdAO2AU4AeMA+2AAQACA+0AuoORGMvDBDANtAPoDBQG2gGDGQz16pRloB0wCkbBKBgFo4As0EBYyZCqoojwDwEACAAA//+W/QFR"

    // Gzip-compressed keyList payload: {"a":[1573573083296714675,8482869187405483569],"r":[8031872927333060586,6829471020522910836]}
    private let keyListPayloadGzip = "H4sIAAAAAAAA/wTAsRHDUAgD0F2ofwEIkPAqPhdZIW0uu/v97GPXHU004ULuMGrYR6XUbIjlXULPPse+dt1yhJibBODjrTmj3GJ4emduuDDP/w0AAP//18WLsl0AAAA="

    private let boundedKeys = [
        "603516ce-1243-400b-b919-0dce5d8aecfd",
        "88f8b33b-f858-4aea-bea2-a5f066bab3ce",
        "375903c8-6f62-4272-88f1-f8bcd304c7ae",
        "18c936ad-0cd2-490d-8663-03eaa23a5ef1",
        "bfd4a824-0cde-4f11-9700-2b4c5ad6f719",
        "4588c4f6-3d18-452a-bc4a-47d7abfd23df",
        "42bcfe02-d268-472f-8ed5-e6341c33b4f7",
        "2a7cae0e-85a2-443e-9d7c-7157b7c5960a",
        "4b0b0467-3fe1-43d1-a3d5-937c0a5473b1",
        "09025e90-d396-433a-9292-acef23cf0ad1"
    ]

    override func setUp() {
        super.setUp()
        decoder = DefaultPayloadDecoder()
    }

    // MARK: - Bounded (bitmap)

    func testBoundedGzipAllKeysFoundInBitmap() throws {
        let keyMap = try decoder.decodeAsBytes(payload: boundedPayloadGzip, compressionType: .gzip)

        for key in boundedKeys {
            let hashedKey = decoder.hashKey(key)
            XCTAssertTrue(decoder.isKeyInBitmap(keyMap: keyMap, hashedKey: hashedKey), "Key \(key) should be in bitmap")
        }
    }

    func testBoundedZlibAllKeysFoundInBitmap() throws {
        let keyMap = try decoder.decodeAsBytes(payload: boundedPayloadZlib, compressionType: .zlib)

        for key in boundedKeys {
            let hashedKey = decoder.hashKey(key)
            XCTAssertTrue(decoder.isKeyInBitmap(keyMap: keyMap, hashedKey: hashedKey), "Key \(key) should be in bitmap")
        }
    }

    func testBoundedRandomKeyLikelyNotInBitmap() throws {
        let keyMap = try decoder.decodeAsBytes(payload: boundedPayloadGzip, compressionType: .gzip)
        let hashedKey = decoder.hashKey("this-key-was-definitely-not-in-the-original-bitmap-zzz-12345")
        // Not an absolute guarantee (could be a false positive), but extremely unlikely
        XCTAssertFalse(decoder.isKeyInBitmap(keyMap: keyMap, hashedKey: hashedKey))
    }

    // MARK: - KeyList

    func testKeyListGzipParsesAddedAndRemoved() throws {
        let jsonString = try decoder.decodeAsString(payload: keyListPayloadGzip, compressionType: .gzip)
        let keyList = try decoder.parseKeyList(jsonString: jsonString)

        XCTAssertEqual(keyList.added.count, 2)
        XCTAssertEqual(keyList.removed.count, 2)
        XCTAssertTrue(keyList.added.contains(1573573083296714675))
        XCTAssertTrue(keyList.added.contains(8482869187405483569))
        XCTAssertTrue(keyList.removed.contains(8031872927333060586))
        XCTAssertTrue(keyList.removed.contains(6829471020522910836))
    }

    // MARK: - isKeyInBitmap edge cases

    func testIsKeyInBitmapWithEmptyDataReturnsFalse() {
        XCTAssertFalse(decoder.isKeyInBitmap(keyMap: Data(), hashedKey: 12345))
    }

    // MARK: - Base64 error

    func testDecodeAsBytesWithInvalidBase64Throws() {
        XCTAssertThrowsError(try decoder.decodeAsBytes(payload: "!!!not-base64!!!", compressionType: .none))
    }
}
