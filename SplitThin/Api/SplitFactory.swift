import Foundation

public protocol SplitFactory: AnyObject {

    /// Default client instance created during factory initialization.
    var client: SplitClient { get }

    /// Returns the client for the given target, or the default client when nil.
    func getClient(_ target: Target?) -> SplitClient

    /// Returns the manager instance.
    func manager() -> SplitManager

    /// Current SDK version.
    var version: String { get }

    /// Tears down all clients and releases resources.
    func destroy() async
}

extension SplitFactory {
    public func getClient() -> SplitClient {
        getClient(nil)
    }
}
