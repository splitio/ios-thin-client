import Foundation
import Logging

public final class DefaultSplitFactory: SplitFactory, @unchecked Sendable {

    private static let kInitErrorMessage =
        "Something happened on Split init and the client couldn't be created"

    private let apiKey: String
    private let defaultTarget: Target
    private let evaluationFilters: EvaluationFilters?

    private var splitManager: SplitManager?
    private var clients = [Target: SplitClient]()
    private var isDestroyed = false

    init(apiKey: String, target: Target, evaluationFilters: EvaluationFilters?) {
        self.apiKey = apiKey
        self.defaultTarget = target
        self.evaluationFilters = evaluationFilters

        self.splitManager = DefaultSplitManager()
        let client = DefaultSplitClient(target: target)
        self.clients[target] = client
    }

    public var client: SplitClient {
        getClient(nil)
    }

    public var version: String {
        Version.sdk
    }

    public func getClient(_ target: Target? = nil) -> SplitClient {
        let resolvedTarget = target ?? defaultTarget
        if let existing = clients[resolvedTarget] {
            return existing
        }

        if isDestroyed {
            Logger.e(Self.kInitErrorMessage)
            return FailedClient()
        }

        let newClient = DefaultSplitClient(target: resolvedTarget)
        clients[resolvedTarget] = newClient
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
