//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

protocol TelemetryTrigger: Sendable {
    func start()
    func stop()
}
