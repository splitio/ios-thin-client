//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import XCTest
import Http
@testable import SplitThin

final class CertificatePinningE2ETest: XCTestCase {

    private let secHelper = SecurityHelper()
    private let appleHost = "developer.apple.com"
    private let validSha256Pin = "sha256/47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
    private var httpMock: RetryableHttpClientMock!
    private var factory: SplitFactory?
    private var prefix: String!

    override func setUp() {
        super.setUp()
        httpMock = RetryableHttpClientMock()
        httpMock.responses = [
            HttpResponse(code: 200, data: AuthE2ETest.mockAuthResponse()),
            HttpResponse(code: 200, data: mockEvaluationsData(flags: []))
        ]
        prefix = "pin_e2e_\(UUID().uuidString.prefix(8))"
        HttpSessionConfig.default.pinChecker = nil
        HttpSessionConfig.default.notificationHandler = nil
    }

    override func tearDown() async throws {
        HttpSessionConfig.default.pinChecker = nil
        HttpSessionConfig.default.notificationHandler = nil
        await factory?.destroy()
        factory = nil
        httpMock = nil
        try await super.tearDown()
    }

    func testFactoryBuildWithPinningWiresHttpSession() throws {
        factory = try buildFactory(retryableHttpClient: httpMock, prefix: prefix, certificatePinning: try makePinningConfig())

        XCTAssertNotNil(factory)
        XCTAssertNotNil(HttpSessionConfig.default.pinChecker)
        XCTAssertNotNil(HttpSessionConfig.default.notificationHandler)
    }

    func testFactoryBuildWithoutPinningDoesNotSetPinCheckerWhenSingletonWasClear() throws {
        HttpSessionConfig.default.pinChecker = nil
        HttpSessionConfig.default.notificationHandler = nil

        factory = try buildFactory(retryableHttpClient: httpMock, prefix: prefix)

        XCTAssertNotNil(factory)
        XCTAssertNil(HttpSessionConfig.default.pinChecker)
        XCTAssertNil(HttpSessionConfig.default.notificationHandler)
    }

    func testFactoryWithPinningDeliversFailureAndStatusToUserHandlers() throws {
        let failureReceived = LockedBox<(String, String)?>(nil)
        let statusReceived = LockedBox<(String, CertificatePinningStatus, String)?>(nil)

        let pinning = try CertificatePinningConfig.builder()
            .addPin(host: appleHost, keyHash: validSha256Pin)
            .set(failureHandler: { host, reason in
                failureReceived.value = (host, reason)
            })
            .set(statusHandler: { host, status, reason in
                statusReceived.value = (host, status, reason)
            })
            .build()

        factory = try buildFactory(retryableHttpClient: httpMock, prefix: prefix, certificatePinning: pinning)

        guard let notificationHandler = HttpSessionConfig.default.notificationHandler else {
            XCTFail("Expected notification handler after factory build")
            return
        }

        notificationHandler.notifyPinningStatus(
            CertificatePinningCompleteStatus(host: appleHost, status: .failed, reason: CredentialValidationResult.credentialNotPinned.description))

        XCTAssertEqual(failureReceived.value?.0, appleHost)
        XCTAssertEqual(failureReceived.value?.1, CredentialValidationResult.credentialNotPinned.description)
        XCTAssertEqual(statusReceived.value?.0, appleHost)
        XCTAssertEqual(statusReceived.value?.1, .failed)
        XCTAssertEqual(statusReceived.value?.2, CredentialValidationResult.credentialNotPinned.description)
    }

    func testSimulatedChallengeCancelsAndNotifiesAfterFactoryBuild() throws {
        let failureReceived = LockedBox<(String, String)?>(nil)
        let expectedHash = secHelper.hashedKey(keyName: "apple_ec_pub", algo: .sha256)
        let keyHash = "sha256/\(expectedHash.base64EncodedString())"

        let pinning = try CertificatePinningConfig.builder()
            .addPin(host: appleHost, keyHash: keyHash)
            .set(failureHandler: { host, reason in
                failureReceived.value = (host, reason)
            })
            .build()

        factory = try buildFactory(retryableHttpClient: httpMock, prefix: prefix, certificatePinning: pinning)

        let challenge = try XCTUnwrap(secHelper.createAuthChallenge(host: appleHost, certName: "apple_ec_cert"))
        let manager = requestManagerFromSessionConfig()
        let disposition = LockedBox<URLSession.AuthChallengeDisposition?>(nil)
        let challengeDone = expectation(description: "pinning challenge completed")

        let task = PinningChallengeURLTaskMock(taskIdentifier: 1)

        manager.urlSession(URLSession.shared, task: task, didReceive: challenge) { dispositionValue, _ in
            disposition.value = dispositionValue
            challengeDone.fulfill()
        }

        wait(for: [challengeDone], timeout: 2.0)
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

private final class PinningChallengeURLTaskMock: URLSessionDataTask, @unchecked Sendable {
    private let id: Int

    init(taskIdentifier: Int) {
        self.id = taskIdentifier
        super.init()
    }

    override var taskIdentifier: Int { id }

    override func resume() {}
}
