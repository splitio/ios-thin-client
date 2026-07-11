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
        provider = DefaultAuthProvider(credentialStorage: storageMock, credentialFetcher: fetcherMock, observer: ObserverSpy())
    }

    func testReturnsCachedCredentialWithoutFetching() async throws {
        provider.register(target: "user1")
        let cached = makeCredential(token: "cached-token")
        storageMock.credentials["user1"] = cached

        let result = try await provider.getCredential()

        XCTAssertEqual(result.token, "cached-token")
        XCTAssertEqual(fetcherMock.fetchCallCount, 0)
    }

    func testFetchesWhenNoCachedCredential() async throws {
        provider.register(target: "user1")
        let fresh = makeCredential(token: "fresh-token")
        fetcherMock.credentialToReturn = fresh

        let result = try await provider.getCredential()

        XCTAssertEqual(result.token, "fresh-token")
        XCTAssertEqual(fetcherMock.fetchCallCount, 1)
        XCTAssertEqual(fetcherMock.lastUsersRequested, ["user1"])
    }

    func testSavesCredentialWithCompositeKey() async throws {
        provider.register(target: "user1")
        let fresh = makeCredential(token: "fresh-token")
        fetcherMock.credentialToReturn = fresh

        try await provider.getCredential()

        XCTAssertEqual(storageMock.saveCallCount, 1)
        XCTAssertEqual(storageMock.credentials["user1"]?.token, "fresh-token")
    }

    func testPropagatesErrorFromFetcher() async {
        provider.register(target: "user1")
        fetcherMock.errorToThrow = CredentialFetcherError.invalidAuthResponse

        do {
            try await provider.getCredential()
            XCTFail("Expected error")
        } catch let error as CredentialFetcherError {
            if case .invalidAuthResponse = error {} else {
                XCTFail("Expected invalidAuthResponse, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testInvalidateUsesCompositeKey() {
        provider.register(target: "user1")
        provider.invalidate(for: "user1")

        XCTAssertEqual(storageMock.invalidateCallCount, 1)
        XCTAssertEqual(storageMock.lastTargetInvalidate, "user1")
    }

    func testConcurrentRequestsShareSingleFetch() async throws {
        provider.register(target: "user1")
        let credential = makeCredential(token: "shared-token")
        fetcherMock.credentialToReturn = credential
        fetcherMock.delay = 0.1

        async let result1 = provider.getCredential()
        async let result2 = provider.getCredential()
        async let result3 = provider.getCredential()

        let results = try await [result1, result2, result3]

        for result in results {
            XCTAssertEqual(result.token, "shared-token")
        }
        XCTAssertEqual(fetcherMock.fetchCallCount, 1)
    }

    func testCompositeKeyUsesAllRegisteredTargetsSorted() async throws {
        provider.register(target: "charlie")
        provider.register(target: "alpha")
        provider.register(target: "bravo")
        let cred = makeCredential(token: "composite-token")
        fetcherMock.credentialToReturn = cred

        try await provider.getCredential()

        XCTAssertEqual(fetcherMock.lastUsersRequested, ["alpha", "bravo", "charlie"])
        XCTAssertNotNil(storageMock.credentials["alpha,bravo,charlie"])
    }

    func testKeyContainingCommaIsNotSplitIntoMultipleUsers() async throws {
        provider.register(target: "CABM, CCIB Ma")
        fetcherMock.credentialToReturn = makeCredential(token: "token")

        try await provider.getCredential()

        XCTAssertEqual(fetcherMock.lastUsersRequested, ["CABM, CCIB Ma"])
    }

    func testRegisterNewTargetInvalidatesOldCompositeKey() async throws {
        provider.register(target: "user1")
        let cred = makeCredential(token: "token")
        fetcherMock.credentialToReturn = cred

        try await provider.getCredential()
        XCTAssertEqual(storageMock.invalidateCallCount, 0)

        provider.register(target: "user2")
        XCTAssertEqual(storageMock.invalidateCallCount, 1)
        XCTAssertEqual(storageMock.lastTargetInvalidate, "user1")
    }

    func testSecondCallUsesCacheAfterFirstFetch() async throws {
        provider.register(target: "user1")
        let cred = makeCredential(token: "token")
        fetcherMock.credentialToReturn = cred

        try await provider.getCredential()
        try await provider.getCredential()

        XCTAssertEqual(fetcherMock.fetchCallCount, 1)
    }

    func testFetchesAgainAfterInvalidate() async throws {
        provider.register(target: "user1")
        let cred = makeCredential(token: "token")
        fetcherMock.credentialToReturn = cred

        try await provider.getCredential()
        provider.invalidate(for: "user1")
        try await provider.getCredential()

        XCTAssertEqual(fetcherMock.fetchCallCount, 2)
    }

    // MARK: - Unregister

    func testUnregisterRemovesTargetFromCompositeKey() async throws {
        provider.register(target: "user1")
        provider.register(target: "user2")
        provider.register(target: "user3")
        fetcherMock.credentialToReturn = makeCredential()

        provider.unregister(target: "user2")

        try await provider.getCredential()

        XCTAssertEqual(storageMock.lastTargetSave, "user1,user3")
    }

    func testUnregisterInvalidatesOldCompositeKey() {
        provider.register(target: "user1")
        provider.register(target: "user2")
        storageMock.invalidateCallCount = 0

        provider.unregister(target: "user2")

        XCTAssertEqual(storageMock.invalidateCallCount, 1)
        XCTAssertEqual(storageMock.lastTargetInvalidate, "user1,user2")
    }

    func testUnregisterNonExistentTargetDoesNothing() {
        provider.register(target: "user1")
        storageMock.invalidateCallCount = 0

        provider.unregister(target: "unknown")

        XCTAssertEqual(storageMock.invalidateCallCount, 0)
    }

    func testUnregisterLastTargetLeavesEmptyKey() async throws {
        provider.register(target: "user1")
        provider.unregister(target: "user1")
        fetcherMock.credentialToReturn = makeCredential()

        try await provider.getCredential()

        XCTAssertEqual(storageMock.lastTargetSave, "")
    }

    func testRegisterSameTargetTwiceDoesNotInvalidate() {
        provider.register(target: "user1")
        provider.register(target: "user1")

        XCTAssertEqual(storageMock.invalidateCallCount, 0)
    }

    // MARK: - Helpers
    private func makeCredential(token: String = "test-token") -> JwtCredential {
        JwtCredential(token: token, expiresAt: Date().addingTimeInterval(3600), pushEnabled: true)
    }
}
