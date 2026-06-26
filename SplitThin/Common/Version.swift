//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

enum Version {
    private static let sdkPlatform = "iOSThin"
    private static let version = "1.0.0-rc4"

    static var semantic: String {
        version
    }

    static var sdk: String {
        "\(sdkPlatform)-\(version)"
    }
}
