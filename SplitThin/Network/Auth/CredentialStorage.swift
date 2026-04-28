//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

protocol CredentialStorage: Sendable {
    func get(for target: String) -> JwtCredential?
    func save(_ credential: JwtCredential, for target: String)
    func invalidate(for target: String)
}

final class DefaultCredentialStorage: CredentialStorage, @unchecked Sendable {

    private var credentials = [String: JwtCredential]()
    private let lock = NSLock()

    func get(for target: String) -> JwtCredential? {
        withLock(lock) {
            guard let credential = credentials[target], credential.expiresAt > Date() else {
                return nil
            }
            return credential
        }
    }

    func save(_ credential: JwtCredential, for target: String) {
        withLock(lock) { credentials[target] = credential }
    }

    func invalidate(for target: String) {
        withLock(lock) { credentials.removeValue(forKey: target) }
    }
}
