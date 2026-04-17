import Foundation

enum ObservableEvent: Sendable {
    case evaluationsUpdated(SdkUpdateMetadata)
    case evaluationsLoadedFromCache(SdkReadyFromCacheMetadata)
    case sdkReadyTimeoutReached
}
