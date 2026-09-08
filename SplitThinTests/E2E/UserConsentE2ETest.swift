//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import XCTest
import Http
@testable import SplitThin

final class UserConsentE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!
    private var factory: SplitFactory!

    override func tearDown() async throws {
        await factory?.destroy()
        factory = nil
        httpMock = nil
        try await super.tearDown()
    }

    // MARK: - Granted

    func testGrantedByDefaultTracksAndSubmits() async throws {
        try buildReadyFactory(userConsent: .granted)

        factory.client.track(eventType: "purchase", value: nil, properties: nil)
        sleep(seconds: 0.3)
        await factory.client.flush()

        XCTAssertEqual(submittedEventTypes(), ["purchase"])
    }

    // MARK: - Unknown

    func testUnknownConsentBuffersButDoesNotSubmit() async throws {
        try buildReadyFactory(userConsent: .unknown)

        factory.client.track(eventType: "purchase", value: nil, properties: nil)
        sleep(seconds: 0.3)
        await factory.client.flush()

        XCTAssertEqual(httpMock.postEventsCalls.count, 0, "Unknown consent must never submit")
    }

    func testGrantingUnknownConsentFlushesBufferedEvents() async throws {
        try buildReadyFactory(userConsent: .unknown)

        factory.client.track(eventType: "purchase", value: nil, properties: nil)
        sleep(seconds: 0.3)
        await factory.client.flush()
        XCTAssertEqual(httpMock.postEventsCalls.count, 0, "Nothing submits while consent is unknown")

        setConsentAndWait(enabled: true)
        await factory.client.flush()

        XCTAssertEqual(submittedEventTypes(), ["purchase"], "Granting must flush the buffered event")
    }

    func testDecliningUnknownConsentDiscardsBufferedEvents() async throws {
        try buildReadyFactory(userConsent: .unknown)

        factory.client.track(eventType: "purchase", value: nil, properties: nil)
        sleep(seconds: 0.3)

        setConsentAndWait(enabled: false)
        setConsentAndWait(enabled: true) // even a later grant has nothing to flush
        await factory.client.flush()

        XCTAssertEqual(httpMock.postEventsCalls.count, 0, "Events buffered under unknown must be discarded on decline")
    }

    // MARK: - Declined

    func testDeclinedConsentNeverSubmits() async throws {
        try buildReadyFactory(userConsent: .declined)

        factory.client.track(eventType: "purchase", value: nil, properties: nil)
        sleep(seconds: 0.3)
        await factory.client.flush()

        XCTAssertEqual(httpMock.postEventsCalls.count, 0, "Declined consent must never submit")
    }

    // MARK: - Runtime transitions

    func testGrantedThenDeclinedStopsSubmitting() async throws {
        try buildReadyFactory(userConsent: .granted)

        setConsentAndWait(enabled: false)
        factory.client.track(eventType: "afterDecline", value: nil, properties: nil)
        sleep(seconds: 0.3)
        await factory.client.flush()

        XCTAssertEqual(httpMock.postEventsCalls.count, 0, "Events tracked after decline must not be submitted")
    }

    func testUserConsentReflectsCurrentValue() async throws {
        try buildReadyFactory(userConsent: .unknown)

        XCTAssertEqual(factory.userConsent, .unknown)

        setConsentAndWait(enabled: true)
        XCTAssertEqual(factory.userConsent, .granted)

        setConsentAndWait(enabled: false)
        XCTAssertEqual(factory.userConsent, .declined)
    }

    // MARK: - Helpers

    private func buildReadyFactory(userConsent: UserConsent) throws {
        httpMock = SecureHttpClientMock()
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))
        factory = try buildFactory(httpClient: httpMock, userConsent: userConsent)

        let sdkReady = expectation("SDK ready")
        factory.client.addEventListener(TestEventListener(readyExpectation: sdkReady))
        waitFor(sdkReady)
    }

    private func setConsentAndWait(enabled: Bool) {
        factory.setUserConsent(enabled: enabled)
        sleep(seconds: 0.3) // consent is applied on a detached Task; let it propagate
    }

    private func submittedEventTypes() -> [String] {
        httpMock.postEventsCalls.flatMap { data in
            (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        }.compactMap { $0["eventTypeId"] as? String }
    }
}
