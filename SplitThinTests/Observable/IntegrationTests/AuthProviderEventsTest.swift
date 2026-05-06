import XCTest
@testable import SplitThin

final class AuthProviderEventsTest: XCTestCase {

    private var storageMock: CredentialStorageMock!
    private var fetcherMock: CredentialFetcherMock!
    private var provider: DefaultAuthProvider!

    override func setUp() {
        super.setUp()
        storageMock = CredentialStorageMock()
        fetcherMock = CredentialFetcherMock()
        provider = DefaultAuthProvider(credentialStorage: storageMock, credentialFetcher: fetcherMock, observer: ObserverSpy())
    }

    override func tearDown() {
        provider = nil
        storageMock = nil
        fetcherMock = nil
        super.tearDown()
    }

    func testCachedCredentialSkipsFetch() async throws {
        provider.register(target: "user1")
        storageMock.credentials["user1"] = makeCredential()

        let result = try await provider.getCredential()

        XCTAssertEqual(result.token, "test-token")
        XCTAssertEqual(fetcherMock.fetchCallCount, 0)
    }

    func testFetchStoresCredential() async throws {
        provider.register(target: "user1")
        fetcherMock.credentialToReturn = makeCredential()

        _ = try await provider.getCredential()

        XCTAssertEqual(storageMock.saveCallCount, 1)
    }

    func testInvalidateRemovesFromStorage() {
        provider.register(target: "user1")
        provider.invalidate(for: "user1")

        XCTAssertEqual(storageMock.invalidateCallCount, 1)
    }

    // MARK: - Helpers

    private func makeCredential() -> JwtCredential {
        JwtCredential(token: "test-token", expiresAt: Date().addingTimeInterval(3600), pushEnabled: true)
    }
}
