import Foundation
import Streaming
@testable import SplitThin

final class SseConnectionHandlerMock: @unchecked Sendable {
    var connectCallCount = 0
    var disconnectCallCount = 0
    var destroyCallCount = 0
    var lastToken: String?
    var lastChannels: [String]?
    var completionToReturn = true

    func connect(token: String, channels: [String], completion: @escaping SseClient.CompletionHandler) {
        connectCallCount += 1
        lastToken = token
        lastChannels = channels
        completion(completionToReturn)
    }

    func disconnect() { disconnectCallCount += 1 }
    func destroy() { destroyCallCount += 1 }
    var isConnectionOpened: Bool = false
}
