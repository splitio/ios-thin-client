//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Tracker
import Logging

final class ThinTrackerLogger: TrackerLogger {

    func log(errorInfo: TrackerValidationError, tag: String) {
        if errorInfo.isError {
            Logger.e("\(tag): \(errorInfo.message ?? "")")
        } else if let message = errorInfo.message {
            Logger.w("\(tag): \(message)")
        }
    }

    func e(message: String, tag: String) {
        Logger.e("\(tag): \(message)")
    }

    func v(_ message: String) {
        Logger.v(message)
    }
}
