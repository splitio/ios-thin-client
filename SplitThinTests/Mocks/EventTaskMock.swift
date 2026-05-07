import Foundation
@testable import SplitThin

final class EventTaskMock: EventTask, @unchecked Sendable {

    var runResult = true
    var runCallCount = 0

    func run() async -> Bool {
        runCallCount += 1
        return runResult
    }
}
