//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import XCTest
import Http
@testable import SplitThin

final class CertificatePinningE2ETest: XCTestCase {

    private let secHelper = SecurityHelper()
    private let appleHost = "developer.apple.com"
    private let validSha256Pin = "sha256/47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
    private var factory: SplitFactory?
    private var prefix: String!

    override func setUp() {
        super.setUp()
        prefix = "pin_e2e_\(UUID().uuidString.prefix(8))"
    }

    override func tearDown() async throws {
        await factory?.destroy()
        factory = nil
        HttpSessionConfig.default.pinChecker = nil
        HttpSessionConfig.default.notificationHandler = nil
        try await super.tearDown()
    }

    func testFactoryBuildWithPinningWiresHttpSession() throws {
        factory = try buildFactory(prefix: prefix, certificatePinning: try makePinningConfig())

        XCTAssertNotNil(factory)
        XCTAssertNotNil(HttpSessionConfig.default.pinChecker)
        XCTAssertNotNil(HttpSessionConfig.default.notificationHandler)
    }

    func testFactoryBuildWithoutPinningDoesNotSetPinCheckerWhenSingletonWasClear() throws {
        HttpSessionConfig.default.pinChecker = nil
        HttpSessionConfig.default.notificationHandler = nil

        factory = try buildFactory(prefix: prefix)

        XCTAssertNotNil(factory)
        XCTAssertNil(HttpSessionConfig.default.pinChecker)
        XCTAssertNil(HttpSessionConfig.default.notificationHandler)
    }

    func testFactoryWithPinningDeliversFailureAndStatusToUserHandlers() throws {
        let failureReceived = LockedBox<(String, String)?>(nil)
        let statusReceived = LockedBox<(String, CertificatePinningStatus, String)?>(nil)
        let failureExpectation = expectation(description: "failure handler")
        let statusExpectation = expectation(description: "status handler")

        let pinning = try CertificatePinningConfig.builder()
            .addPin(host: appleHost, keyHash: validSha256Pin)
            .set(failureHandler: { host, reason in
                failureReceived.value = (host, reason)
                failureExpectation.fulfill()
            })
            .set(statusHandler: { host, status, reason in
                statusReceived.value = (host, status, reason)
                statusExpectation.fulfill()
            })
            .build()

        factory = try buildFactory(prefix: prefix, certificatePinning: pinning)

        guard let notificationHandler = HttpSessionConfig.default.notificationHandler else {
            XCTFail("Expected notification handler after factory build")
            return
        }

        notificationHandler.notifyPinningStatus(
            CertificatePinningCompleteStatus(host: appleHost, status: .failed, reason: CredentialValidationResult.credentialNotPinned.description))

        wait(for: [failureExpectation, statusExpectation], timeout: 1.0)
        XCTAssertEqual(failureReceived.value?.0, appleHost)
        XCTAssertEqual(failureReceived.value?.1, CredentialValidationResult.credentialNotPinned.description)
        XCTAssertEqual(statusReceived.value?.0, appleHost)
        XCTAssertEqual(statusReceived.value?.1, .failed)
        XCTAssertEqual(statusReceived.value?.2, CredentialValidationResult.credentialNotPinned.description)
    }

    func testSimulatedChallengeCancelsAndNotifiesAfterFactoryBuild() throws {
        let failureReceived = LockedBox<(String, String)?>(nil)
        let failureExpectation = expectation(description: "failure handler on challenge")
        let expectedHash = secHelper.hashedKey(keyName: "apple_ec_pub", algo: .sha256)
        let keyHash = "sha256/\(expectedHash.base64EncodedString())"

        let pinning = try CertificatePinningConfig.builder()
            .addPin(host: appleHost, keyHash: keyHash)
            .set(failureHandler: { host, reason in
                failureReceived.value = (host, reason)
                failureExpectation.fulfill()
            })
            .build()

        factory = try buildFactory(prefix: prefix, certificatePinning: pinning)

        let challenge = try XCTUnwrap(secHelper.createAuthChallenge(host: appleHost, certName: "apple_ec_cert"))
        let manager = requestManagerFromSessionConfig()
        let disposition = LockedBox<URLSession.AuthChallengeDisposition?>(nil)
        let challengeDone = expectation(description: "challenge completed")

        let request = URLRequest(url: URL(string: "https://\(appleHost)/")!)
        let task = URLSession.shared.dataTask(with: request)

        manager.urlSession(URLSession.shared, task: task, didReceive: challenge) { dispositionValue, _ in
            disposition.value = dispositionValue
            challengeDone.fulfill()
        }

        wait(for: [challengeDone, failureExpectation], timeout: 2.0)
        XCTAssertEqual(disposition.value, .cancelAuthenticationChallenge)
        XCTAssertEqual(failureReceived.value?.0, appleHost)
        XCTAssertEqual(failureReceived.value?.1, CredentialValidationResult.invalidChain.description)
    }

    private func makePinningConfig() throws -> CertificatePinningConfig {
        try CertificatePinningConfig.builder()
            .addPin(host: "api.split.io", keyHash: validSha256Pin)
            .build()
    }

    private func requestManagerFromSessionConfig() -> DefaultHttpRequestManager {
        DefaultHttpRequestManager(authenticator: HttpSessionConfig.default.authenticator, pinChecker: HttpSessionConfig.default.pinChecker, notificationHandler: HttpSessionConfig.default.notificationHandler)
    }
}
