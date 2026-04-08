import Foundation

public protocol SplitEventListener: Sendable {
    func onReady(_ metadata: SdkReadyMetadata)
    func onReadyFromCache(_ metadata: SdkReadyFromCacheMetadata)
    func onReadyTimedOut()
    func onUpdate(_ metadata: SdkUpdateMetadata)
}

// Default implementation to allow the customer to implement just what they need
public extension SplitEventListener {
    func onReady(_ metadata: SdkReadyMetadata) {}
    func onReadyFromCache(_ metadata: SdkReadyFromCacheMetadata) {}
    func onReadyTimedOut() {}
    func onUpdate(_ metadata: SdkUpdateMetadata) {}
}
