import XCTest
@testable import SplitThin

final class DefaultSplitFactoryTest: XCTestCase {

    private func makeFactory(matchingKey: String = "user1") -> DefaultSplitFactory {
        DefaultSplitFactory(sdkKey: SdkKey("api-key"),
                            target: Target(matchingKey: matchingKey),
                            evaluationFilters: nil)
    }

    // MARK: - client property

    func testClientPropertyReturnsDefault() {
        let factory = makeFactory()

        XCTAssertEqual(factory.client.target.matchingKey, "user1")
    }

    func testClientPropertyReturnsSameAsGetClientNil() {
        let factory = makeFactory()

        XCTAssertTrue(factory.client === factory.getClient(nil))
    }

    // MARK: - getClient

    func testGetClientDefaultTarget() {
        let factory = makeFactory()

        let client = factory.getClient()

        XCTAssertEqual(client.target.matchingKey, "user1")
    }

    func testGetClientExplicitNilReturnsDefault() {
        let factory = makeFactory()

        let client = factory.getClient(nil)

        XCTAssertEqual(client.target.matchingKey, "user1")
    }

    func testGetClientDifferentTarget() {
        let factory = makeFactory()

        let client = factory.getClient(Target(matchingKey: "user2"))

        XCTAssertEqual(client.target.matchingKey, "user2")
    }

    func testGetClientReturnsSameInstanceForSameKey() {
        let factory = makeFactory()
        let target = Target(matchingKey: "user2")

        let client1 = factory.getClient(target)
        let client2 = factory.getClient(target)

        XCTAssertTrue(client1 === client2, "Should return the same instance for the same key")
    }

    func testGetClientReturnsSameInstanceForSameKeyDifferentAttributes() {
        let factory = makeFactory()

        let client1 = factory.getClient(Target(matchingKey: "user2", attributes: ["env": "prod"]))
        let client2 = factory.getClient(Target(matchingKey: "user2", attributes: ["env": "staging"]))

        XCTAssertTrue(client1 === client2, "Should return the same instance when matchingKey and bucketingKey match")
    }

    func testGetClientReturnsDifferentInstancesForDifferentKeys() {
        let factory = makeFactory()

        let client1 = factory.getClient(Target(matchingKey: "user2"))
        let client2 = factory.getClient(Target(matchingKey: "user3"))

        XCTAssertFalse(client1 === client2, "Should return different instances for different keys")
    }

    // MARK: - Version

    func testVersion() {
        let factory = makeFactory()

        XCTAssertFalse(factory.version.isEmpty)
        XCTAssertTrue(factory.version.contains("ios-thin"))
    }

    // MARK: - Manager

    func testManagerReturnsInstance() {
        let factory = makeFactory()

        let mgr = factory.manager()

        XCTAssertTrue(mgr is DefaultSplitManager)
    }

    func testManagerReturnsSameInstance() {
        let factory = makeFactory()

        let mgr1 = factory.manager()
        let mgr2 = factory.manager()

        XCTAssertTrue(mgr1 === mgr2, "Should return the same manager instance")
    }

    // MARK: - Destroy

    func testDestroyReturnsFailedClientForNewTargets() async {
        let factory = makeFactory()

        await factory.destroy()

        let client = factory.getClient(Target(matchingKey: "user2"))
        XCTAssertTrue(client is FailedClient)
    }

    func testDestroyMultipleCalls() async {
        let factory = makeFactory()

        await factory.destroy()
        await factory.destroy()
    }

    func testGetClientDefaultAfterDestroy() async {
        let factory = makeFactory()

        await factory.destroy()

        let client = factory.getClient()
        XCTAssertEqual(client.target.matchingKey, "",
                       "After destroy, default client should be FailedClient")
    }

    func testManagerAfterDestroy() async {
        let factory = makeFactory()

        await factory.destroy()

        let mgr = factory.manager()
        XCTAssertTrue(mgr is FailedManager)
    }
}
