import Foundation
@testable import SplitThin

final class TelemetrySubmitterMock: TelemetrySubmitter, @unchecked Sendable {

    var flushCalls = [Int?]()
    private let lock = NSLock()

    func flush(count: Int?) async {
        withLock(lock) {
            flushCalls.append(count)
        }
    }
}
