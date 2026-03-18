import Foundation
@testable import SplitThin

final class AuthProviderMock: AuthProvider, @unchecked Sendable {

    var credentialToReturn: JwtCredential?
    var errorToThrow: Error?
    var getCredentialCallCount = 0

    func getCredential() async throws -> JwtCredential {
        getCredentialCallCount += 1
        if let error = errorToThrow {
            throw error
        }
        guard let credential = credentialToReturn else {
            fatalError("AuthProviderMock: credentialToReturn not set")
        }
        return credential
    }
}
