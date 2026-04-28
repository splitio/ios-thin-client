//  Created by Gaston Thea
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

private let kOccupancyPrefix = "[?occupancy=metrics.publishers]"
private let kPublishersMetadata = "channel-metadata:publishers"

protocol SseJwtParser {
    func extractChannels(from jwt: String) -> [String]?
}

final class DefaultSseJwtParser: SseJwtParser {

    func extractChannels(from jwt: String) -> [String]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else {
            Logger.e("SseJwtParser: invalid JWT structure")
            return nil
        }

        var base64 = String(parts[1])
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        base64 = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let capabilityString = payload["x-ably-capability"] as? String,
              let capabilityData = capabilityString.data(using: .utf8),
              let channelMap = try? JSONSerialization.jsonObject(with: capabilityData) as? [String: [String]] else {
            Logger.e("SseJwtParser: failed to parse JWT payload")
            return nil
        }

        return channelMap.map { channelName, permissions in
            if permissions.contains(kPublishersMetadata) {
                return "\(kOccupancyPrefix)\(channelName)"
            }
            return channelName
        }
    }
}
