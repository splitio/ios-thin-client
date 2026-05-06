import XCTest
@testable import SplitThin

final class DefaultSplitManagerTest: XCTestCase {

    private var repoMock: EvaluationRepositoryMock!
    private var manager: DefaultSplitManager!

    private let target = Target(matchingKey: "user1")

    override func setUp() {
        super.setUp()
        repoMock = EvaluationRepositoryMock()
        manager = DefaultSplitManager(evaluationRepository: repoMock, target: target)
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
}
