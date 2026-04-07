import Foundation
@testable import SplitThin

final class EvaluationProviderMock: EvaluationProvider, @unchecked Sendable {

    var resultToReturn: EvaluationsResult?
    var fetchCalls: [(target: Target, filters: EvaluationFilters?)] = []
    var fetchDelay: UInt64 = 0

    private let lock = NSLock()

    func fetch(target: Target, filters: EvaluationFilters?) async -> EvaluationsResult? {
        withLock(lock) { fetchCalls.append((target, filters)) }

        if fetchDelay > 0 {
            try? await Task.sleep(nanoseconds: fetchDelay)
        }

        return resultToReturn
    }
}
