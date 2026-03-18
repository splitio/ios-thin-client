import Foundation

/// Returned when factory initialization fails, to avoid crashing the host app.
final class FailedClient: SplitClient {

    var target: Target {
        Target(matchingKey: "")
    }

    func destroy() {}
}
