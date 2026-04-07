import Foundation

struct JwtCredential: Sendable {
    let token: String
    let expiresAt: Date
    let pushEnabled: Bool

    init(token: String, expiresAt: Date, pushEnabled: Bool) {
        self.token = token
        self.expiresAt = expiresAt
        self.pushEnabled = pushEnabled
    }
}
