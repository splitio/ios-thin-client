import XCTest
import Http
@testable import SplitThin

final class ManagerE2ETest: XCTestCase {

    private var httpMock: SecureHttpClientMock!
    private var factory: SplitFactory!

    override func setUp() {
        super.setUp()
        httpMock = SecureHttpClientMock()
    }

    override func tearDown() async throws {
        await factory?.destroy()
        factory = nil
        httpMock = nil 
        try await super.tearDown()
    }

    func testGetFlagNamesAggregatesAcrossActiveClients() async throws {
        // Each client gets distinct flags plus one shared name, to prove union + dedup.
        httpMock.fetchEvaluationsResultByKey["user-A"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a", "shared"])))
        httpMock.fetchEvaluationsResultByKey["user-B"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_b", "shared"])))

        let prefix = "manager_e2e_\(UUID().uuidString.prefix(8))"
        let readyA = expectation("Client A ready")
        let readyB = expectation("Client B ready")
        factory = try buildFactory(httpClient: httpMock, target: Target(matchingKey: "user-A", trafficType: "user"), prefix: prefix)
        factory.client.addEventListener(TestEventListener(readyExpectation: readyA))
        let clientB = factory.getClient("user-B")
        clientB.addEventListener(TestEventListener(readyExpectation: readyB))

        waitFor(readyA, readyB)

        // Both clients' caches populate asynchronously; wait until the manager sees both before asserting.
        waitUntil(timeout: 2) { Set(self.factory.manager().getFlagNames()).isSuperset(of: ["flag_a", "flag_b"]) }

        let names = factory.manager().getFlagNames()
        XCTAssertEqual(Set(names), ["flag_a", "flag_b", "shared"], "Manager must union flag names from every active client")
        XCTAssertEqual(names.count, 3, "Shared flag names must be deduped across clients")
    }

    func testSetTargetDoesNotEmptyManagerFlagNames() async throws {
        httpMock.fetchEvaluationsResultByKey["user-A"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_a"])))
        httpMock.fetchEvaluationsResultByKey["user-B"] = .success(HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag_b"])))

        let prefix = "manager_settarget_\(UUID().uuidString.prefix(8))"
        let readyA = expectation("Client A ready")
        factory = try buildFactory(httpClient: httpMock, target: Target(matchingKey: "user-A", trafficType: "user"), prefix: prefix)
        factory.client.addEventListener(TestEventListener(readyExpectation: readyA))
        waitFor(readyA)

        XCTAssertEqual(factory.manager().getFlagNames(), ["flag_a"], "flag names should reflect the initial target")

        factory.getClient(Target(matchingKey: "user-B", trafficType: "user"))

        // The new target's fetch is async; wait until the manager reflects it, then assert it never went empty.
        waitUntil(timeout: 3) { self.factory.manager().getFlagNames().contains("flag_b") }
        let names = factory.manager().getFlagNames()
        XCTAssert(names.notEmpty, "setTarget must not leave the manager with no flag names")
        XCTAssertTrue(Set(names).isSuperset(of: ["flag_b", "flag_a"]), "the manager must reflect the new target's flags after setTarget")
    }
}
