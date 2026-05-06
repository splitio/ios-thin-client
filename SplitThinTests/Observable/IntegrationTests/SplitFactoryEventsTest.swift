import XCTest
@testable import SplitThin

final class SplitFactoryEventsTest: XCTestCase {

    private var factory: SplitFactory!
    private var observerSpy: ObserverSpy!

    override func setUp() {
        super.setUp()
        observerSpy = ObserverSpy()
        factory = try! buildFactory(httpClient: SecureHttpClientMock(), observer: observerSpy)
    }

    override func tearDown() async throws {
        await factory.destroy()
        factory = nil
        observerSpy = nil
    }

    func testInitEmitsFactoryLifecycleEvents() {
        XCTAssertTrue(observerSpy.eventNames.contains("factoryInitStarted"))
        XCTAssertTrue(observerSpy.eventNames.contains("factoryInitCompleted"))
        XCTAssertTrue(observerSpy.eventNames.contains("clientCreated"))
    }

    func testInitEmitsEventsInOrder() {
        let names = observerSpy.eventNames
        guard let initStart = names.firstIndex(of: "factoryInitStarted"),
              let clientCreated = names.firstIndex(of: "clientCreated"),
              let initEnd = names.firstIndex(of: "factoryInitCompleted") else {
            XCTFail("Missing expected events")
            return
        }
        XCTAssertLessThan(initStart, clientCreated)
        XCTAssertLessThan(clientCreated, initEnd)
    }

    func testGetClientEmitsClientCreated() {
        let countBefore = observerSpy.eventNames.filter { $0 == "clientCreated" }.count

        factory.getClient("user2")

        let countAfter = observerSpy.eventNames.filter { $0 == "clientCreated" }.count
        XCTAssertEqual(countAfter, countBefore + 1)
    }

    func testGetClientSameTargetDoesNotEmitAgain() {
        let countBefore = observerSpy.eventNames.filter { $0 == "clientCreated" }.count

        factory.getClient("user-123") // Same ID as the test factory

        let countAfter = observerSpy.eventNames.filter { $0 == "clientCreated" }.count
        XCTAssertEqual(countAfter, countBefore)
    }

    func testDestroyEmitsDestroyEvents() async {
        await factory.destroy()

        XCTAssertTrue(observerSpy.eventNames.contains("destroyStarted"))
        XCTAssertTrue(observerSpy.eventNames.contains("destroyCompleted"))
    }
}
