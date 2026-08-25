//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import XCTest
@testable import SplitThin

final class SplitFactoryUserConsentTest: XCTestCase {

    private var factory: SplitFactory!

    override func tearDown() async throws {
        await factory?.destroy()
        factory = nil
    }

    func testDefaultConsentIsGranted() throws {
        factory = try buildFactory(httpClient: SecureHttpClientMock())

        XCTAssertEqual(factory.userConsent, .granted)
    }

    func testInitialConsentFromConfig() throws {
        factory = try buildFactory(httpClient: SecureHttpClientMock(), userConsent: .unknown)

        XCTAssertEqual(factory.userConsent, .unknown)
    }

    func testSetUserConsentEnabledGrants() throws {
        factory = try buildFactory(httpClient: SecureHttpClientMock(), userConsent: .unknown)

        factory.setUserConsent(enabled: true)

        XCTAssertEqual(factory.userConsent, .granted)
    }

    func testSetUserConsentDisabledDeclines() throws {
        factory = try buildFactory(httpClient: SecureHttpClientMock(), userConsent: .unknown)

        factory.setUserConsent(enabled: false)

        XCTAssertEqual(factory.userConsent, .declined)
    }
}
