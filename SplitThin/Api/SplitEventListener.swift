import Foundation

public protocol SplitEventListener: Sendable {
    func onReady(_ metadata: SdkReadyMetadata)
    func onReadyFromCache(_ metadata: SdkReadyFromCacheMetadata)
    func onUpdate(_ metadata: SdkUpdateMetadata)
}

public extension SplitEventListener {
    func onReady(_ metadata: SdkReadyMetadata) {}
    func onReadyFromCache(_ metadata: SdkReadyFromCacheMetadata) {}
    func onUpdate(_ metadata: SdkUpdateMetadata) {}
}