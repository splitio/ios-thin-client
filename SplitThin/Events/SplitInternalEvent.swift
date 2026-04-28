//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

enum SplitInternalEvent: Sendable {
    case evaluationsUpdated(SdkUpdateMetadata)
    case evaluationsLoadedFromCache(SdkReadyFromCacheMetadata)
    case sdkReadyTimeoutReached
}