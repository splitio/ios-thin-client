//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

public protocol SplitManager: AnyObject {
    func getFlagNames() -> [String]
}

final class DefaultSplitManager: SplitManager {

    private let evaluationRepository: EvaluationRepository
    var activeTargetsProvider: () -> [Target]

    init(evaluationRepository: EvaluationRepository, activeTargetsProvider: @escaping () -> [Target] = { [] }) {
        self.evaluationRepository = evaluationRepository
        self.activeTargetsProvider = activeTargetsProvider
    }

    func getFlagNames() -> [String] {
        // Union across active clients, deduping while preserving first-seen order.
        var seen = Set<String>()
        var result = [String]()
        for target in activeTargetsProvider() {
            for name in evaluationRepository.getFlagNames(target: target) where seen.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }
}
