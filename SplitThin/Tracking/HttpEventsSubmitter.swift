//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

protocol HttpEventsSubmitter: Sendable {
    func submit(payload: Data, target: Target) async throws
}

final class DefaultHttpEventsSubmitter: HttpEventsSubmitter {

    private let secureHttpClient: SecureHttpClient

    init(secureHttpClient: SecureHttpClient) {
        self.secureHttpClient = secureHttpClient
    }

    func submit(payload: Data, target: Target) async throws {
        _ = try await secureHttpClient.postEvents(payload: payload)
    }
}
