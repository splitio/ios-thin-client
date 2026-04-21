import XCTest
@testable import SplitThin

final class AuthProviderEventsTest: XCTestCase {

    private var storageMock: CredentialStorageMock!
    private var fetcherMock: CredentialFetcherMock!
    private var provider: DefaultAuthProvider!
    private var observerSpy: ObserverSpy!

    override func setUp() {
        super.setUp()
        storageMock = CredentialStorageMock()
        fetcherMock = CredentialFetcherMock()
        observerSpy = ObserverSpy()
        provider = DefaultAuthProvider(credentialStorage: storageMock, credentialFetcher: fetcherMock, observer: observerSpy)
    }

    override func tearDown() {
        provider = nil
        storageMock = nil
        fetcherMock = nil
        observerSpy = nil
        super.tearDown()
    }

    func testCachedCredentialEmitsJwtRequestStartedCached() async throws {
        storageMock.credentials["user1"] = makeCredential()

        _ = try await provider.getCredential(for: "user1")

        XCTAssertEqual(observerSpy.eventNames, ["jwtRequestStarted"])
        if case .jwtRequestStarted(let cached) = observerSpy.notifiedEvents.first {
            XCTAssertTrue(cached)
        } else {
            XCTFail("Expected jwtRequestStarted(cached: true)")
        }
    }

    func testFetchEmitsJwtRequestStartedNotCachedAndStored() async throws {
        fetcherMock.credentialToReturn = makeCredential()

        _ = try await provider.getCredential(for: "user1")

        XCTAssertTrue(observerSpy.eventNames.contains("jwtRequestStarted"))
        XCTAssertTrue(observerSpy.eventNames.contains("jwtStored"))
    }

    func testInvalidateEmitsJwtExpiredOrInvalid() {
        provider.invalidate(for: "user1")

        XCTAssertEqual(observerSpy.eventNames, ["jwtExpiredOrInvalid"])
    }

    // MARK: - Helpers

    private func makeCredential() -> JwtCredential {
        JwtCredential(token: "test-token", expiresAt: Date().addingTimeInterval(3600), pushEnabled: true)
    }
}
