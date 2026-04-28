//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

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
