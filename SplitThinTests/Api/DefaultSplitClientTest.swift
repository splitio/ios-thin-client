import XCTest
@testable import SplitThin

final class DefaultSplitClientTest: XCTestCase {

    private var client: DefaultSplitClient!
    private var treatmentsManagerMock: TreatmentsManagerMock!

    override func setUp() {
        super.setUp()
        treatmentsManagerMock = TreatmentsManagerMock()
        client = DefaultSplitClient(
            target: Target(matchingKey: "user1"),
            treatmentsManager: treatmentsManagerMock
        )
    }

    override func tearDown() {
        client = nil
        treatmentsManagerMock = nil
        super.tearDown()
    }

    func testSetTargetUpdatesTarget() {
        client.setTarget(target: Target(matchingKey: "user2"))

        XCTAssertEqual(client.target.key.matchingKey, "user2")
    }

    func testGetTreatmentReturnsControl() {
        let result = client.getTreatment(flag: "flag_a", evaluationOptions: nil)

        XCTAssertEqual(result.treatment, "control")
    }

    func testGetTreatmentsReturnsControlForAll() {
        let results = client.getTreatments(flags: ["flag_a", "flag_b"], evaluationOptions: nil)

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.treatment == "control" })
    }

    func testDestroyIsIdempotent() async {
        await client.destroy()
        await client.destroy()
    }
}
