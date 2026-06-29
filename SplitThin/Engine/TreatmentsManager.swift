//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

protocol TreatmentsManager: Sendable {
    func getTreatment(flag: String) -> EvaluationResult
    func getTreatments(flags: [String]) -> [EvaluationResult]
    func getTreatmentsByFlagSets(flagSets: [String]) -> [EvaluationResult]
    func setTarget(_ target: Target)
}

final class DefaultTreatmentsManager: TreatmentsManager, @unchecked Sendable {

    private var target: Target
    private let evaluationRepository: EvaluationRepository
    private let fallbackCalculator: FallbackTreatmentsCalculator
    private let lock = NSLock()

    init(target: Target, evaluationRepository: EvaluationRepository, fallbackCalculator: FallbackTreatmentsCalculator) {
        self.target = target
        self.evaluationRepository = evaluationRepository
        self.fallbackCalculator = fallbackCalculator
    }

    func getTreatment(flag: String) -> EvaluationResult {
        let currentTarget = withLock(lock) { target }
        return evaluationRepository.getEvaluation(flag: flag, target: currentTarget)?.evaluationResult
            ?? controlResult(flag: flag)
    }

    func getTreatments(flags: [String]) -> [EvaluationResult] {
        let currentTarget = withLock(lock) { target }
        let storedEvaluations = evaluationRepository.getEvaluations(flags: flags, target: currentTarget)
        let resultsByFlag = Dictionary(uniqueKeysWithValues: storedEvaluations.map { ($0.evaluationResult.flag, $0.evaluationResult) })
        return flags.map { resultsByFlag[$0] ?? controlResult(flag: $0) }
    }

    func getTreatmentsByFlagSets(flagSets: [String]) -> [EvaluationResult] {
        let currentTarget = withLock(lock) { target }
        return evaluationRepository.getEvaluationsByFlagSets(flagSets, target: currentTarget).map { $0.evaluationResult }
    }

    func setTarget(_ target: Target) {
        withLock(lock) { self.target = target }
        evaluationRepository.setTarget(target)
    }

    private func controlResult(flag: String) -> EvaluationResult {
        let fallback = fallbackCalculator.resolve(flagName: flag, label: nil)
        return EvaluationResult(flag: flag, treatment: fallback.treatment, flagSets: [], config: fallback.config)
    }
}
