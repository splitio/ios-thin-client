//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

struct AuthResponse: DynamicDecodable {
    let token: String
    let pushEnabled: Bool
    let connDelay: Int?

    init(jsonObject: Any) throws {
        guard let dict = jsonObject as? [String: Any] else {
            throw JsonError.invalidData
        }
        guard let token = dict["token"] as? String else {
            throw JsonError.parsingFailed
        }

        self.token = token

        // Parse nested config.streaming structure
        if let config = dict["config"] as? [String: Any],
           let streaming = config["streaming"] as? [String: Any] {
            pushEnabled = streaming["enabled"] as? Bool ?? false
            connDelay = streaming["delay"] as? Int
        } else {
            // Legacy flat format
            pushEnabled = dict["pushEnabled"] as? Bool ?? false
            connDelay = dict["connDelay"] as? Int
        }
    }
}
