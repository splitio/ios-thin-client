import Foundation
import Logging

public enum SplitThinMain {
    public static func messages() -> [String] {
        [
            "SplitThin main"
        ]
    }

    public static func main() {
        // Ensure logs are actually emitted (Logger defaults to `.none`)
        Logger.shared.level = .info
        messages().forEach { message in
            Logger.i(message)
        }
    }
}
