//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import XCTest
import Security
import Http
@testable import SplitThin

/// Exercises the `Http` module pinning primitives the thin client relies on, using simulated
/// challenges backed by real DER certificates. Mirrors the realistic scope of ios-client's tests:
/// a self-signed/untrusted chain cannot reach `.success`, so we assert the reachable outcomes.
final class CertificatePinningCheckerTests: XCTestCase {

    private let secHelper = SecurityHelper()
    private let validHost = "developer.apple.com"

    // MARK: - challenge-level results

    func testNonServerTrustMethodIsSkipped() {
        let checker = DefaultTlsPinChecker(pins: [CredentialPin(host: validHost, hash: Data(), algo: .sha256)])
        let challenge = secHelper.createInvalidChallenge(authMethod: NSURLAuthenticationMethodClientCertificate)

        XCTAssertEqual(checker.check(credential: challenge), .noServerTrustMethod)
    }

    func testMissingServerTrust() {
        let checker = DefaultTlsPinChecker(pins: [CredentialPin(host: validHost, hash: Data(), algo: .sha256)])
        let challenge = secHelper.createChallengeWithoutSecTrust()

        XCTAssertEqual(checker.check(credential: challenge), .unavailableServerTrust)
    }

    func testInvalidCredentialParameter() {
        let checker = DefaultTlsPinChecker(pins: [CredentialPin(host: validHost, hash: Data(), algo: .sha256)])

        XCTAssertEqual(checker.check(credential: [String: String]() as AnyObject), .invalidParameter)
    }

    func testNoPinsForDomain() throws {
        let checker = DefaultTlsPinChecker(pins: [CredentialPin(host: "other.split.io", hash: Data(), algo: .sha256)])
        let challenge = try XCTUnwrap(secHelper.createAuthChallenge(host: "unpinned.split.io", certName: "apple_ec_cert"))

        XCTAssertEqual(checker.check(credential: challenge), .noPinsForDomain)
    }

    func testUntrustedCertificateFailsChainValidation() throws {
        let expectedHash = secHelper.hashedKey(keyName: "apple_ec_pub", algo: .sha256)
        let checker = DefaultTlsPinChecker(pins: [CredentialPin(host: validHost, hash: expectedHash, algo: .sha256)])
        let challenge = try XCTUnwrap(secHelper.createAuthChallenge(host: validHost, certName: "apple_ec_cert"))

        // The certificate's key matches the pin, but the chain is not trusted by the OS,
        // so validation stops at chain evaluation before reaching a pinning success.
        XCTAssertEqual(checker.check(credential: challenge), .invalidChain)
    }

    // MARK: - SPKI extraction

    func testSpkiExtractionMatchesPublicKey() throws {
        let certData = try XCTUnwrap(TestCerts.data(named: "apple_ec_cert")) as NSData
        let cert = try XCTUnwrap(SecCertificateCreateWithData(nil, certData))

        let spki = try XCTUnwrap(TlsCertificateParser.spki(from: cert))

        XCTAssertEqual(spki.type, .secp256r1)
        XCTAssertEqual(spki.data, TestCerts.data(named: "apple_ec_pub"))
    }
}

// MARK: - Host matching

final class HostDomainFilterTests: XCTestCase {

    private func pin(_ host: String) -> CredentialPin {
        CredentialPin(host: host, hash: Data([0x01]), algo: .sha256)
    }

    func testExactMatch() {
        let pins = [pin("api.split.io")]
        XCTAssertEqual(HostDomainFilter.pinsFor(host: "api.split.io", pins: pins).count, 1)
        XCTAssertEqual(HostDomainFilter.pinsFor(host: "other.split.io", pins: pins).count, 0)
    }

    func testSingleLevelWildcard() {
        let pins = [pin("*.split.io")]
        XCTAssertEqual(HostDomainFilter.pinsFor(host: "sub.split.io", pins: pins).count, 1)
        XCTAssertEqual(HostDomainFilter.pinsFor(host: "a.b.split.io", pins: pins).count, 0)
    }

    func testMultiLevelWildcard() {
        let pins = [pin("**.split.io")]
        XCTAssertEqual(HostDomainFilter.pinsFor(host: "sub.split.io", pins: pins).count, 1)
        XCTAssertEqual(HostDomainFilter.pinsFor(host: "a.b.split.io", pins: pins).count, 1)
    }
}

// MARK: - Notification handler

final class ThinPinningNotificationHandlerTests: XCTestCase {

    func testFailureHandlerReceivesHostAndReasonFromFailedStatus() {
        let received = LockedBox<(String, String)?>(nil)
        let handler = ThinPinningNotificationHandler(failureHandler: { received.value = ($0, $1) }, statusHandler: nil)

        handler.notifyPinningStatus(CertificatePinningCompleteStatus(host: "api.split.io", status: .failed, reason: "Credential is not pinned"))

        XCTAssertEqual(received.value?.0, "api.split.io")
        XCTAssertEqual(received.value?.1, "Credential is not pinned")
    }

    func testFailureHandlerNotCalledOnSuccessStatus() {
        let failureCalled = LockedBox(false)
        let handler = ThinPinningNotificationHandler(failureHandler: { _, _ in failureCalled.value = true }, statusHandler: nil)

        handler.notifyPinningStatus(CertificatePinningCompleteStatus(host: "api.split.io", status: .success, reason: "Success"))

        XCTAssertEqual(failureCalled.value, false)
    }

    func testReasonlessFailureNotificationDoesNotCallFailureHandler() {
        let failureCalled = LockedBox(false)
        let handler = ThinPinningNotificationHandler(failureHandler: { _, _ in failureCalled.value = true }, statusHandler: nil)

        // The Http layer's reason-less failure hook must not drive the public handler;
        // failures are surfaced through notifyPinningStatus(.failed) instead.
        handler.notifyPinningFailure(host: "api.split.io")

        XCTAssertEqual(failureCalled.value, false)
    }

    func testStatusHandlerReceivesEveryOutcome() {
        let received = LockedBox<(String, CertificatePinningStatus, String)?>(nil)
        let handler = ThinPinningNotificationHandler(failureHandler: nil, statusHandler: { received.value = ($0, $1, $2) })

        handler.notifyPinningStatus(CertificatePinningCompleteStatus(host: "api.split.io", status: .failed, reason: "Boom"))

        XCTAssertEqual(received.value?.0, "api.split.io")
        XCTAssertEqual(received.value?.1, .failed)
        XCTAssertEqual(received.value?.2, "Boom")
    }
}

/// Thread-safe mutable box so `@Sendable` handler closures can record values under strict concurrency.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) { _value = value }

    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
