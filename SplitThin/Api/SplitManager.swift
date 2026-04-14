import Foundation

public protocol SplitManager: AnyObject {
    func getFlagNames() -> [String]
}

final class DefaultSplitManager: SplitManager {

    private let evaluationRepository: EvaluationRepository
    private let target: Target

    init(evaluationRepository: EvaluationRepository, target: Target) {
        self.evaluationRepository = evaluationRepository
        self.target = target
    }

    func getFlagNames() -> [String] {
        evaluationRepository.getFlagNames(target: target)
    }
}
