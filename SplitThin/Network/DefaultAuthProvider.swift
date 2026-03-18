import Foundation

final class DefaultAuthProvider: AuthProvider, @unchecked Sendable {

    func getCredential() async throws -> JwtCredential {
        // TODO: Implement actual auth flow against authServiceEndpoint
        fatalError("Not implemented")
    }
}
