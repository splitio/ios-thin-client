//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

public enum LogLevel: String, Sendable {
    case none = "NONE"
    case error = "ERROR"
    case warning = "WARNING"
    case info = "INFO"
    case debug = "DEBUG"
    case verbose = "VERBOSE"
}
