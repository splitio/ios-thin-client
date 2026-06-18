import Foundation
@testable import SplitThin

final class EventTaskMock: EventTask, @unchecked Sendable {

    var runResult: EventTaskResult = .success
    var runCallCount = 0

    func run() async -> EventTaskResult {
        runCallCount += 1
        return runResult
    }
}
