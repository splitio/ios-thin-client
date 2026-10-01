//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

protocol RolloutCacheManager: Sendable {
    func validateCache() async
}

final class DefaultRolloutCacheManager: RolloutCacheManager, Sendable {

    private static let kMinCacheClearDays = 1
    private static let kSecondsPerDay = 86_400

    private let storage: CoreDataStorage
    private let configuration: RolloutCacheConfiguration
    private let evaluationRepository: EvaluationRepository

    init(storage: CoreDataStorage, configuration: RolloutCacheConfiguration, evaluationRepository: EvaluationRepository) {
        self.storage = storage
        self.configuration = configuration
        self.evaluationRepository = evaluationRepository
    }

    func validateCache() async {
        if await shouldClear() {
            await clear()
        }
    }

    private func shouldClear() async -> Bool {
        let lastUpdateTimestamp = await storage.getUpdateTimestamp()
        let now = Self.nowSeconds()
        let daysSinceLastUpdate = Self.secondsToDays(now - lastUpdateTimestamp)

        if lastUpdateTimestamp > 0 && daysSinceLastUpdate >= configuration.expirationDays {
            Logger.i("Clearing rollout cache due to expiration")
            return true
        }

        if configuration.clearOnInit {
            let lastCacheClearTimestamp = await storage.getRolloutCacheLastClearTimestamp()
            let daysSinceCacheClear = Self.secondsToDays(now - lastCacheClearTimestamp)
            if daysSinceCacheClear >= Self.kMinCacheClearDays {
                Logger.i("Forcing rollout cache clear on init")
                return true
            }
            Logger.d("Rollout cache was cleared recently. Skipping")
        }

        return false
    }

    private func clear() async {
        await storage.clearAllRolloutData()
        evaluationRepository.clear()
        await storage.setRolloutCacheLastClearTimestamp(Self.nowSeconds())
        Logger.i("Rollout cache cleared")
    }

    private static func nowSeconds() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    private static func secondsToDays(_ seconds: Int64) -> Int {
        Int(seconds / Int64(kSecondsPerDay))
    }
}
