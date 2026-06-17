import XCTest
import Http
@testable import SplitThin

final class FlagSetsE2ETest: XCTestCase {

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

    func testGetTreatmentsByFlagSetsReturnsFlagsInThatSet() async throws {
        // mockEvaluationsData places every flag in set "set-a".
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1", "flag2"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, prefix: "flagsets_\(UUID().uuidString.prefix(8))")
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        let bySet = factory.client.getTreatmentsByFlagSets(flagSets: ["set-a"]).map { $0.flag }.sorted()
        XCTAssertEqual(bySet, ["flag1", "flag2"], "Both flags belong to set-a")
    }

    func testGetTreatmentsByFlagSetsReturnsEmptyForUnknownSet() async throws {
        httpMock.fetchEvaluationsResult = HttpResponse(code: 200, data: mockEvaluationsData(flags: ["flag1"]))

        let sdkReady = expectation("SDK ready")
        let listener = TestEventListener(readyExpectation: sdkReady)
        factory = try buildFactory(httpClient: httpMock, prefix: "flagsets_\(UUID().uuidString.prefix(8))")
        factory.client.addEventListener(listener)
        waitFor(sdkReady)

        XCTAssertTrue(factory.client.getTreatmentsByFlagSets(flagSets: ["set-z"]).isEmpty)
    }
}
