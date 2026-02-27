import XCTest
@testable import SplitThin
import Logging

private final class CapturingLogPrinter: LogPrinter {
    private(set) var calls: [[Any]] = []

    func stdout(_ items: Any...) {
        calls.append(items)
    }
}

final class SplitThinTests: XCTestCase {
    func testMain() {
        let printer = CapturingLogPrinter()
        let prevPrinter = Logger.shared.printer
        let prevLevel = Logger.shared.level
        Logger.shared.printer = printer
        defer {
            Logger.shared.printer = prevPrinter
            Logger.shared.level = prevLevel
        }

        SplitThinMain.main()
        XCTAssertEqual(SplitThinMain.messages(), ["SplitThin main"])

        let loggedMessages = printer.calls.compactMap { $0.last as? String }
        XCTAssertTrue(loggedMessages.contains("SplitThin main"))
    }
}
