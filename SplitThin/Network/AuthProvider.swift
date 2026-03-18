import Foundation

protocol AuthProvider: Sendable {
    func getCredential() async throws -> JwtCredential
}
