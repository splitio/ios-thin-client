//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

// Adds ConfigsEnabled (from the SplitConfig) to the cache logic equation.
// If it changes, the cache is invalidated.
// Can be extended with future requisites.
protocol CacheValidator: Sendable {
    func fingerprint(for target: Target) -> String
    func isValid(storedAttrHash: String?, for target: Target) -> Bool
}

final class DefaultCacheValidator: CacheValidator, Sendable {

    private let configsEnabled: Bool

    init(configsEnabled: Bool) {
        self.configsEnabled = configsEnabled
    }

    func fingerprint(for target: Target) -> String {
        let attributesHash = Murmur3Hash.attributesHash(for: target.attributes)
        return String(Murmur3Hash.hashString(attributesHash, configsEnabled ? 1 : 0)) // We use "configsEnabled" as seed
    }

    func isValid(storedAttrHash: String?, for target: Target) -> Bool {
        guard let storedAttrHash else { return true }
        return storedAttrHash == fingerprint(for: target)
    }
}
