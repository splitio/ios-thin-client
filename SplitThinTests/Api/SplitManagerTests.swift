import XCTest
@testable import SplitThin

final class DefaultSplitManagerTest: XCTestCase {

    private var repoMock: EvaluationRepositoryMock!
    private var manager: DefaultSplitManager!

    private let target = Target(matchingKey: "user1", trafficType: "user")

    override func setUp() {
        super.setUp()
        repoMock = EvaluationRepositoryMock()
        manager = DefaultSplitManager(evaluationRepository: repoMock, activeTargetsProvider: { [self.target] })
    }

    func testGetFlagNamesReturnsRepositoryValues() {
        repoMock.flagNamesToReturn = ["flag_a", "flag_b", "flag_c"]

        let result = manager.getFlagNames()

        XCTAssertEqual(result, ["flag_a", "flag_b", "flag_c"])
    }

    func testGetFlagNamesReturnsEmptyWhenNoFlags() {
        repoMock.flagNamesToReturn = []

        let result = manager.getFlagNames()

        XCTAssertTrue(result.isEmpty)
    }

    func testGetFlagNamesAggregatesAcrossActiveTargets() {
        let targetA = Target(matchingKey: "user-A", trafficType: "user")
        let targetB = Target(matchingKey: "user-B", trafficType: "user")
        repoMock.flagNamesByKey["user-A"] = ["flag_a", "shared"]
        repoMock.flagNamesByKey["user-B"] = ["flag_b", "shared"]

        let manager = DefaultSplitManager(evaluationRepository: repoMock, activeTargetsProvider: { [targetA, targetB] })

        let result = manager.getFlagNames()

        XCTAssertEqual(Set(result), ["flag_a", "flag_b", "shared"], "Manager must union flag names from every active client")
        XCTAssertEqual(result.count, 3, "Flag names shared across clients must be deduped")
    }
}
