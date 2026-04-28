//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

public enum SdkUpdateMetadataType: Sendable {
    case flagsUpdate
    case segmentsUpdate
}

public struct SdkUpdateMetadata: Sendable {
    public let type: SdkUpdateMetadataType
    public let names: [String]
    public let changeNumber: Int64?

    public init(type: SdkUpdateMetadataType, names: [String], changeNumber: Int64? = nil) {
        self.type = type
        self.names = names
        self.changeNumber = changeNumber
    }
}

public struct SdkReadyMetadata: Sendable {
    public let lastUpdateTimestamp: Int64?
    public let isInitialCacheLoad: Bool

    public init(lastUpdateTimestamp: Int64? = nil, isInitialCacheLoad: Bool) {
        self.lastUpdateTimestamp = lastUpdateTimestamp
        self.isInitialCacheLoad = isInitialCacheLoad
    }
}

// Structure equal to SdkReadyMetadata, but could diverge in the future.
public struct SdkReadyFromCacheMetadata: Sendable {
    public let lastUpdateTimestamp: Int64?
    public let isInitialCacheLoad: Bool

    public init(lastUpdateTimestamp: Int64? = nil, isInitialCacheLoad: Bool) {
        self.lastUpdateTimestamp = lastUpdateTimestamp
        self.isInitialCacheLoad = isInitialCacheLoad
    }
}
