import Foundation

public enum SdkUpdateMetadataType: Sendable {
    case flagsUpdate
    case segmentsUpdate
}

public struct SdkUpdateMetadata: Sendable {
    public let type: SdkUpdateMetadataType
    public let names: [String]

    public init(type: SdkUpdateMetadataType, names: [String]) {
        self.type = type
        self.names = names
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
