import Foundation

enum SplitInternalEvent: Sendable {
    case evaluationsUpdated(SdkUpdateMetadata)
    case evaluationsLoadedFromCache(SdkReadyFromCacheMetadata)
    case sdkReadyTimeoutReached
}