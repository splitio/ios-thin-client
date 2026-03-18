import Foundation

public protocol SplitFactory {

    /// Default client instance created during factory initialization.
    var client: SplitClient { get }

    /// Current SDK version.
    var version: String { get }

    /// Returns the client for the given target, or the default client if nil.
    func getClient(_ target: Target?) -> SplitClient

    /// Returns the manager instance.
    func manager() -> SplitManager

    /// Tears down all clients and releases resources.
    func destroy() async
}