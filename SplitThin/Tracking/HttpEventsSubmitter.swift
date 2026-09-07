//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

protocol HttpEventsSubmitter: Sendable {
    func submit(payload: Data) async throws
}

final class DefaultHttpEventsSubmitter: HttpEventsSubmitter {

    private let secureHttpClient: SecureHttpClient

    init(secureHttpClient: SecureHttpClient) {
        self.secureHttpClient = secureHttpClient
    }

    func submit(payload: Data) async throws {
        let response = try await secureHttpClient.postEvents(payload: payload)
        if response.code == 401 {
            throw CredentialFetcherError.unauthorized
        }
    }
}
