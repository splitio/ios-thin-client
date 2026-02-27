import XCTest
@testable import SplitThin

final class SplitThinTests: XCTestCase {
    func testMain() {
        SplitThinMain.main()
        XCTAssertEqual(SplitThinMain.messages(), ["SplitThin main"])
    }
}
