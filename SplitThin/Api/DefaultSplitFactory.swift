import Foundation
import Logging

public final class DefaultSplitFactory: SplitFactory, @unchecked Sendable {

    private static let kInitErrorMessage =
        "Something happened on Split init and the client couldn't be created"

    private let sdkKey: SdkKey
    private let defaultTarget: Target
    private let defaultKey: Key
    private let evaluationFilters: EvaluationFilters?

    private var splitManager: SplitManager?
    private var clients = [Key: SplitClient]()
    private var isDestroyed = false

    init(sdkKey: SdkKey, target: Target, evaluationFilters: EvaluationFilters?) {
        self.sdkKey = sdkKey
        self.defaultTarget = target
        self.defaultKey = target.key
        self.evaluationFilters = evaluationFilters

        self.splitManager = DefaultSplitManager()
        let client = DefaultSplitClient(target: target)
        self.clients[target.key] = client
    }

    public var client: SplitClient {
        getClient(nil)
    }

    public var version: String {
        Version.sdk
    }

    public func getClient(_ target: Target? = nil) -> SplitClient {
        let resolvedKey = target?.key ?? defaultKey
        if let existing = clients[resolvedKey] {
            return existing
        }

        if isDestroyed {
            Logger.e(Self.kInitErrorMessage)
            return FailedClient()
        }

        let resolvedTarget = target ?? defaultTarget
        let newClient = DefaultSplitClient(target: resolvedTarget)
        clients[resolvedKey] = newClient
        return newClient
    }

    public func manager() -> SplitManager {
        if let manager = splitManager {
            return manager
        }
        Logger.e(Self.kInitErrorMessage)
        return FailedManager()
    }

    public func destroy() async {
        guard !isDestroyed else { return }
        isDestroyed = true
        clients.values.forEach { $0.destroy() }
        clients.removeAll()
        splitManager = nil
    }
}
