import XCTest
@testable import SplitThin

final class SplitThinTests: XCTestCase {
    func testMain() {
        XCTAssertEqual(SplitThinMain.messages(), ["SplitThin main"])
    }
}
