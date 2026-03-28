import Foundation

public protocol SplitManager: AnyObject {
    func getFlagNames() -> [String]
}

final class DefaultSplitManager: SplitManager {

    private let evaluationRepository: EvaluationRepository

    init(evaluationRepository: EvaluationRepository) {
        self.evaluationRepository = evaluationRepository
    }

    func getFlagNames() -> [String] {
        evaluationRepository.getFlagNames()
    }
}
