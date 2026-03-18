import Foundation

public struct JwtCredential: Sendable {
    public let token: String
    public let expiresAt: Date
    public let pushEnabled: Bool

    public init(token: String, expiresAt: Date, pushEnabled: Bool) {
        self.token = token
        self.expiresAt = expiresAt
        self.pushEnabled = pushEnabled
    }
}
