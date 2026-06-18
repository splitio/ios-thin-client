//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

public enum SyncMode: String, Sendable {
    case streaming = "STREAMING"
    case polling = "POLLING"
    case singleSync = "SINGLE_SYNC"
}
