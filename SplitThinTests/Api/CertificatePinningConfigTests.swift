//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import XCTest
import Http
@testable import SplitThin

final class CertificatePinningConfigTests: XCTestCase {

    // A valid base64-encoded 32-byte value (sha256 of an empty input).
    private let validSha256 = "sha256/47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
    private let secHelper = SecurityHelper()

    // MARK: - keyHash pins

    func testAddPinWithValidKeyHash() throws {
        let config = try CertificatePinningConfig.builder()
            .addPin(host: "api.split.io", keyHash: validSha256)
            .build()

        XCTAssertEqual(config.pins.count, 1)
        XCTAssertEqual(config.pins.first?.host, "api.split.io")
        XCTAssertEqual(config.pins.first?.algo, .sha256)
        XCTAssertEqual(config.pins.first?.hash.count, 32)
    }

    func testAddPinWithSha1KeyHash() throws {
        // sha1 of empty input, base64-encoded (20 bytes).
        let config = try CertificatePinningConfig.builder()
            .addPin(host: "api.split.io", keyHash: "sha1/2jmj7l5rSw0yVb/vlWAYkK/YBwk=")
            .build()

        XCTAssertEqual(config.pins.first?.algo, .sha1)
        XCTAssertEqual(config.pins.first?.hash.count, 20)
    }

    func testKeyHashMissingSeparatorThrows() {
        assertBuildThrows(
            CertificatePinningConfig.builder().addPin(host: "api.split.io", keyHash: "sha256NoSlash"),
            expected: .invalidKeyHashFormat(host: "api.split.io"))
    }

    func testKeyHashUnsupportedAlgorithmThrows() {
        assertBuildThrows(
            CertificatePinningConfig.builder().addPin(host: "api.split.io", keyHash: "md5/AAAA"),
            expected: .unsupportedAlgorithm(algorithm: "md5"))
    }

    func testKeyHashInvalidBase64Throws() {
        assertBuildThrows(
            CertificatePinningConfig.builder().addPin(host: "api.split.io", keyHash: "sha256/@@@not-base64@@@"),
            expected: .invalidKeyHashEncoding(host: "api.split.io", algorithm: "sha256"))
    }

    func testKeyHashEmptyThrows() {
        assertBuildThrows(
            CertificatePinningConfig.builder().addPin(host: "api.split.io", keyHash: "sha256/"),
            expected: .emptyKeyHash(host: "api.split.io", algorithm: "sha256"))
    }

    // MARK: - certificate pins

    func testAddPinWithCertificateMatchesPublicKeyHash() throws {
        let builder = CertificatePinningConfig.builder()
        builder.bundle = TestCerts.makeBundle(names: ["apple_ec_cert"])
        let config = try builder
            .addPin(host: "apple.com", certificateName: "apple_ec_cert")
            .build()

        XCTAssertEqual(config.pins.count, 1)
        XCTAssertEqual(config.pins.first?.algo, .sha256)
        // The pin is the SPKI hash of the certificate's public key, which must equal
        // the hash of the public-key DER for the same key pair.
        XCTAssertEqual(config.pins.first?.hash, secHelper.hashedKey(keyName: "apple_ec_pub", algo: .sha256))
    }

    func testAddPinWithRsaCertificateMatchesPublicKeyHash() throws {
        let builder = CertificatePinningConfig.builder()
        builder.bundle = TestCerts.makeBundle(names: ["rsa_2048_cert"])
        let config = try builder
            .addPin(host: "rsa.split.io", certificateName: "rsa_2048_cert")
            .build()

        XCTAssertEqual(config.pins.first?.hash, secHelper.hashedKey(keyName: "rsa_2048_pub", algo: .sha256))
    }

    func testMissingCertificateThrows() {
        let builder = CertificatePinningConfig.builder()
        builder.bundle = TestCerts.makeBundle(names: [])
        assertBuildThrows(
            builder.addPin(host: "apple.com", certificateName: "does_not_exist"),
            expected: .certificateParsingFailed(certificateName: "does_not_exist"))
    }

    // MARK: - handlers & multiple pins

    func testHandlersAreStored() throws {
        let config = try CertificatePinningConfig.builder()
            .addPin(host: "api.split.io", keyHash: validSha256)
            .set(failureHandler: { _, _ in })
            .set(statusHandler: { _, _, _ in })
            .build()

        XCTAssertNotNil(config.failureHandler)
        XCTAssertNotNil(config.statusHandler)
    }

    func testHandlersDefaultToNil() throws {
        let config = try CertificatePinningConfig.builder()
            .addPin(host: "api.split.io", keyHash: validSha256)
            .build()

        XCTAssertNil(config.failureHandler)
        XCTAssertNil(config.statusHandler)
    }

    func testMultiplePinsPreserveOrder() throws {
        let builder = CertificatePinningConfig.builder()
        builder.bundle = TestCerts.makeBundle(names: ["apple_ec_cert"])
        let config = try builder
            .addPin(host: "a.split.io", keyHash: validSha256)
            .addPin(host: "b.split.io", certificateName: "apple_ec_cert")
            .build()

        XCTAssertEqual(config.pins.count, 2)
        XCTAssertEqual(config.pins[0].host, "a.split.io")
        XCTAssertEqual(config.pins[1].host, "b.split.io")
    }

    // MARK: - helper

    private func assertBuildThrows(_ builder: CertificatePinningConfig.Builder, expected: CertificatePinningError, file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try builder.build()
            XCTFail("Expected build() to throw \(expected)", file: file, line: line)
        } catch let error as CertificatePinningError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected CertificatePinningError, got \(error)", file: file, line: line)
        }
    }
}
