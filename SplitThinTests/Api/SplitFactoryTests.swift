import XCTest
@testable import SplitThin

final class DefaultSplitFactoryTest: XCTestCase {

    private var factory: DefaultSplitFactory!
    private var secureHttpClientMock: SecureHttpClientMock!
    private var authProviderMock: AuthProviderMock!
    private var evaluationRepositoryMock: EvaluationRepositoryMock!
    private var fetchCoordinatorMock: EvaluationFetchCoordinatorMock!
    private var connectionManagerMock: StreamingMock!
    private var evaluationStorageMock: EvaluationStorageMock!

    override func setUp() {
        super.setUp()
        secureHttpClientMock = SecureHttpClientMock()
        authProviderMock = AuthProviderMock()
        authProviderMock.credentialToReturn = JwtCredential(token: "mock", expiresAt: Date().addingTimeInterval(3600), pushEnabled: false)
        evaluationRepositoryMock = EvaluationRepositoryMock()
        fetchCoordinatorMock = EvaluationFetchCoordinatorMock()
        connectionManagerMock = StreamingMock()
        evaluationStorageMock = EvaluationStorageMock()
        let splitManager = DefaultSplitManager(evaluationRepository: evaluationRepositoryMock)
        let coreDataStorage = CoreDataStorage(databaseName: "test_factory_\(UUID().uuidString.prefix(8))")
        factory = DefaultSplitFactory(sdkKey: SdkKey("api-key"), target: Target(matchingKey: "user1", trafficType: "user"), config: SplitClientConfig.builder().build(), evaluationFilters: nil, secureHttpClient: secureHttpClientMock, authProvider: authProviderMock, evaluationRepository: evaluationRepositoryMock, fetchCoordinator: fetchCoordinatorMock, streaming: connectionManagerMock, evaluationStorage: evaluationStorageMock, coreDataStorage: coreDataStorage, splitManager: splitManager, factoryObserver: ObserverSpy(), telemetryStorage: DefaultTelemetryStorage(storage: coreDataStorage))
    }

    override func tearDown() async throws {
        await factory.destroy()
        factory = nil
        secureHttpClientMock = nil
        authProviderMock = nil
        evaluationRepositoryMock = nil
        fetchCoordinatorMock = nil
        connectionManagerMock = nil
        evaluationStorageMock = nil
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
        let client = factory.getClient("user2")

        XCTAssertEqual(client.target.key.matchingKey, "user2")
    }

    func testGetClientReturnsSameInstanceForSameKey() {
        let target = Target(matchingKey: "user2", trafficType: "user")

        let client1 = factory.getClient(target)
        let client2 = factory.getClient(target)

        XCTAssertIdentical(client1, client2, "Should return the same instance for the same key")
    }

    func testGetClientReturnsSameInstanceForSameKeyDifferentAttributes() {
        let client1 = factory.getClient(Target(matchingKey: "user2", attributes: ["env": "prod"], trafficType: "user"))
        let client2 = factory.getClient(Target(matchingKey: "user2", attributes: ["env": "staging"], trafficType: "user"))

        XCTAssertIdentical(client1, client2, "Should return the same instance when matchingKey and bucketingKey match")
    }

    func testGetClientWithSameKeyDifferentTargetRoutesNewTarget() {
        let client1 = factory.getClient(Target(matchingKey: "user2", attributes: ["env": "prod"], trafficType: "user"))
        let client2 = factory.getClient(Target(matchingKey: "user2", attributes: ["env": "staging"], trafficType: "account"))

        XCTAssertIdentical(client1, client2, "Same key must return the same instance")

        // The new target is routed in the background (fire-and-forget setTarget).
        waitUntil(timeout: 2) {
            (client2.target.attributes?["env"] as? String) == "staging" && client2.target.trafficType == "account"
        }
        XCTAssertEqual(client2.target.attributes?["env"] as? String, "staging", "New attributes must be applied, not dropped")
        XCTAssertEqual(client2.target.trafficType, "account", "New trafficType must be applied, not dropped")
    }

    func testGetClientReturnsDifferentInstancesForDifferentKeys() {
        let client1 = factory.getClient("user2")
        let client2 = factory.getClient("user3")

        XCTAssertNotIdentical(client1, client2, "Should return different instances for different keys")
    }

    // MARK: - Push disabled fallback

    func testFactoryRegistersPushDisabledHandler() {
        XCTAssertNotNil(connectionManagerMock.pushDisabledHandler, "Factory should wire the shared streaming's push-disabled fallback handler")
    }

    func testClientCreatedAfterPushDisabledPolls() async {
        let fetchCoordinator = EvaluationFetchCoordinatorMock()
        let streamingMock = StreamingMock()
        let evalRepo = EvaluationRepositoryMock()
        let coreData = CoreDataStorage(databaseName: "test_latefallback_\(UUID().uuidString.prefix(8))")
        let config = SplitClientConfig.builder().set(syncMode: .streaming).setMinEvaluationRefreshRate(1).set(evaluationRefreshRate: 1).build()
        let localFactory = DefaultSplitFactory(sdkKey: SdkKey("api-key"), target: Target(matchingKey: "user1", trafficType: "user"), config: config, evaluationFilters: nil, secureHttpClient: SecureHttpClientMock(), authProvider: AuthProviderMock(), evaluationRepository: evalRepo, fetchCoordinator: fetchCoordinator, streaming: streamingMock, evaluationStorage: EvaluationStorageMock(), coreDataStorage: coreData, splitManager: DefaultSplitManager(evaluationRepository: evalRepo), factoryObserver: ObserverSpy(), telemetryStorage: DefaultTelemetryStorage(storage: coreData))

        // Server disables push: existing clients fall back to polling.
        streamingMock.pushDisabledHandler?()

        // A client created AFTER the toggle must also come up in polling, not streaming.
        _ = localFactory.getClient(Target(matchingKey: "user-456", trafficType: "user"))

        let polledForLateClient: () -> Bool = {
            fetchCoordinator.fetchCalls.contains { call in
                guard call.target.matchingKey == "user-456" else { return false }
                if call.reason == .periodic { return true }
                return false
            }
        }

        waitUntil(timeout: 5) { polledForLateClient() }
        await localFactory.destroy()
    }

    // MARK: - Version

    func testVersion() {
        XCTAssertFalse(factory.version.isEmpty)
        XCTAssertTrue(factory.version.contains("iOSThin"))
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

        let client = factory.getClient("user2")
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
