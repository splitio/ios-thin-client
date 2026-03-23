import Foundation

protocol TreatmentsManager: Sendable {
    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult
    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult]
    func setTarget(_ target: Target) async
}

final class DefaultTreatmentsManager: TreatmentsManager, @unchecked Sendable {

    private var target: Target
    private let evaluationRepository: EvaluationRepository
    private let lock = NSLock()

    init(target: Target, evaluationRepository: EvaluationRepository) {
        self.target = target
        self.evaluationRepository = evaluationRepository
    }

    func getTreatment(flag: String, evaluationOptions: EvaluationOptions?) async -> EvaluationResult {
        let currentTarget = withLock(lock) { target }
        return await evaluationRepository.getTreatment(flag: flag, target: currentTarget) ?? EvaluationResult(flag: flag, treatment: "control", flagSets: [])
    }

    func getTreatments(flags: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        let currentTarget = withLock(lock) { target }
        let results = await evaluationRepository.getTreatments(flags: flags, target: currentTarget)
        let resultsByFlag = Dictionary(uniqueKeysWithValues: results.map { ($0.flag, $0) })
        return flags.map { resultsByFlag[$0] ?? EvaluationResult(flag: $0, treatment: "control", flagSets: []) }
    }

    func getTreatmentsByFlagSets(flagSets: [String], evaluationOptions: EvaluationOptions?) async -> [EvaluationResult] {
        let currentTarget = withLock(lock) { target }
        return await evaluationRepository.getTreatmentsByFlagSets(flagSets, target: currentTarget)
    }

    func setTarget(_ target: Target) async {
        withLock(lock) { self.target = target }
        await evaluationRepository.setTarget(target)
    }
}
