//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

struct JwtCredential: Sendable {
    let token: String
    let expiresAt: Date
    let pushEnabled: Bool
    let connDelay: Int?

    init(token: String, expiresAt: Date, pushEnabled: Bool, connDelay: Int? = nil) {
        self.token = token
        self.expiresAt = expiresAt
        self.pushEnabled = pushEnabled
        self.connDelay = connDelay
    }
}
