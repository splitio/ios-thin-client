import XCTest
@testable import SplitThin

final class DefaultAuthProviderTest: XCTestCase {

    private var storageMock: CredentialStorageMock!
    private var fetcherMock: CredentialFetcherMock!
    private var provider: DefaultAuthProvider!

    override func setUp() {
        super.setUp()
        storageMock = CredentialStorageMock()
        fetcherMock = CredentialFetcherMock()
        provider = DefaultAuthProvider(credentialStorage: storageMock, credentialFetcher: fetcherMock)
    }

    func testReturnsCachedCredentialWithoutFetching() async throws {
        let cached = makeCredential(token: "cached-token")
        storageMock.credentials["user1"] = cached

        let result = try await provider.getCredential(for: "user1")

        XCTAssertEqual(result.token, "cached-token")
        XCTAssertEqual(fetcherMock.fetchCallCount, 0)
    }

    func testFetchesWhenNoCachedCredential() async throws {
        let fresh = makeCredential(token: "fresh-token")
        fetcherMock.credentialToReturn = fresh

        let result = try await provider.getCredential(for: "user1")

        XCTAssertEqual(result.token, "fresh-token")
        XCTAssertEqual(fetcherMock.fetchCallCount, 1)
        XCTAssertEqual(fetcherMock.lastUsersRequested, ["user1"])
    }

    func testSavesCredentialAfterFetch() async throws {
        let fresh = makeCredential(token: "fresh-token")
        fetcherMock.credentialToReturn = fresh

        try await provider.getCredential(for: "user1")

        XCTAssertEqual(storageMock.saveCallCount, 1)
        XCTAssertEqual(storageMock.credentials["user1"]?.token, "fresh-token")
    }

    func testPropagatesErrorFromFetcher() async {
        fetcherMock.errorToThrow = CredentialFetcherError.invalidAuthResponse

        do {
            try await provider.getCredential(for: "user1")
            XCTFail("Expected error")
        } catch let error as CredentialFetcherError {
            if case .invalidAuthResponse = error {} else {
                XCTFail("Expected invalidAuthResponse, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testInvalidateDelegatesToStorage() {
        provider.invalidate(for: "user1")

        XCTAssertEqual(storageMock.invalidateCallCount, 1)
        XCTAssertEqual(storageMock.lastTargetInvalidate, "user1")
    }

    func testConcurrentRequestsShareSingleFetch() async throws {
        let credential = makeCredential(token: "shared-token")
        fetcherMock.credentialToReturn = credential
        fetcherMock.delay = 0.1

        async let result1 = provider.getCredential(for: "user1")
        async let result2 = provider.getCredential(for: "user1")
        async let result3 = provider.getCredential(for: "user1")

        let results = try await [result1, result2, result3]

        for result in results {
            XCTAssertEqual(result.token, "shared-token")
        }
        XCTAssertEqual(fetcherMock.fetchCallCount, 1)
    }

    func testDifferentTargetsFetchIndependently() async throws {
        let cred = makeCredential(token: "token")
        fetcherMock.credentialToReturn = cred

        try await provider.getCredential(for: "user1")
        try await provider.getCredential(for: "user2")

        XCTAssertEqual(fetcherMock.fetchCallCount, 2)
    }

    func testSecondCallUsesCacheAfterFirstFetch() async throws {
        let cred = makeCredential(token: "token")
        fetcherMock.credentialToReturn = cred

        try await provider.getCredential(for: "user1")
        try await provider.getCredential(for: "user1")

        XCTAssertEqual(fetcherMock.fetchCallCount, 1)
    }

    func testFetchesAgainAfterInvalidate() async throws {
        let cred = makeCredential(token: "token")
        fetcherMock.credentialToReturn = cred

        try await provider.getCredential(for: "user1")
        provider.invalidate(for: "user1")
        try await provider.getCredential(for: "user1")

        XCTAssertEqual(fetcherMock.fetchCallCount, 2)
    }

    // MARK: - Helpers
    private func makeCredential(token: String = "test-token") -> JwtCredential {
        JwtCredential(token: token, expiresAt: Date().addingTimeInterval(3600), pushEnabled: true)
    }
}
