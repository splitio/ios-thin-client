import XCTest
@testable import SplitThin

final class DefaultSplitFactoryTest: XCTestCase {

    private var factory: DefaultSplitFactory!
    private var secureHttpClientMock: SecureHttpClientMock!
    private var evaluationRepositoryMock: EvaluationRepositoryMock!
    private var syncManagerMock: SyncManagerMock!
    private var splitManager: DefaultSplitManager!

    override func setUp() {
        super.setUp()
        secureHttpClientMock = SecureHttpClientMock()
        evaluationRepositoryMock = EvaluationRepositoryMock()
        syncManagerMock = SyncManagerMock()
splitManager = DefaultSplitManager(evaluationRepository: evaluationRepositoryMock, target: Target(matchingKey: "user1"))
        factory = DefaultSplitFactory(sdkKey: SdkKey("api-key"), target: Target(matchingKey: "user1"), config: SplitClientConfig.builder().build(), evaluationFilters: nil, secureHttpClient: secureHttpClientMock, evaluationRepository: evaluationRepositoryMock, syncManager: syncManagerMock, splitManager: splitManager)
    }

    override func tearDown() async throws {
        await factory.destroy()
        factory = nil
        secureHttpClientMock = nil
        evaluationRepositoryMock = nil
        syncManagerMock = nil
        splitManager = nil
    }

    // MARK: - client property

    func testClientPropertyReturnsDefault() {
        XCTAssertEqual(factory.client.target.key.matchingKey, "user1")
    }

    // MARK: - getClient

    func testGetClientDefaultTarget() {
        let client = factory.getClient()

        XCTAssertEqual(client.target.key.matchingKey, "user1")
    }

    func testGetClientNilReturnsDefaultClient() {
        let client = factory.getClient(nil)

        XCTAssertEqual(client.target.key.matchingKey, "user1")
        XCTAssertIdentical(client, factory.client)
    }

    func testGetClientDifferentTarget() {
        let client = factory.getClient(Target(matchingKey: "user2"))

        XCTAssertEqual(client.target.key.matchingKey, "user2")
    }

    func testGetClientReturnsSameInstanceForSameKey() {
        let target = Target(matchingKey: "user2")

        let client1 = factory.getClient(target)
        let client2 = factory.getClient(target)

        XCTAssertIdentical(client1, client2, "Should return the same instance for the same key")
    }

    func testGetClientReturnsSameInstanceForSameKeyDifferentAttributes() {
        let client1 = factory.getClient(Target(matchingKey: "user2", attributes: ["env": "prod"]))
        let client2 = factory.getClient(Target(matchingKey: "user2", attributes: ["env": "staging"]))

        XCTAssertIdentical(client1, client2, "Should return the same instance when matchingKey and bucketingKey match")
    }

    func testGetClientReturnsDifferentInstancesForDifferentKeys() {
        let client1 = factory.getClient(Target(matchingKey: "user2"))
        let client2 = factory.getClient(Target(matchingKey: "user3"))

        XCTAssertNotIdentical(client1, client2, "Should return different instances for different keys")
    }

    // MARK: - Version

    func testVersion() {
        XCTAssertFalse(factory.version.isEmpty)
        XCTAssertTrue(factory.version.contains("ios-thin"))
    }

    // MARK: - Manager

    func testManagerReturnsInstance() {
        XCTAssertTrue(factory.manager() is DefaultSplitManager)
    }

    func testManagerReturnsSameInstance() {
        let mgr1 = factory.manager()
        let mgr2 = factory.manager()

        XCTAssertIdentical(mgr1, mgr2, "Should return the same manager instance")
    }

    // MARK: - Destroy

    func testDestroyReturnsFailedClientForNewTargets() async {
        await factory.destroy()

        let client = factory.getClient(Target(matchingKey: "user2"))
        XCTAssertTrue(client is FailedClient)
    }

    func testDestroyMultipleCalls() async {
        await factory.destroy()
        await factory.destroy()
    }

    func testClientAfterDestroyReturnsFailedClient() async {
        await factory.destroy()
        XCTAssertTrue(factory.client is FailedClient)
    }

    func testManagerAfterDestroy() async {
        await factory.destroy()

        XCTAssertTrue(factory.manager() is FailedManager)
    }
}
