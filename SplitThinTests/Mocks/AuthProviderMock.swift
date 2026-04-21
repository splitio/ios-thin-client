import Foundation
@testable import SplitThin

final class AuthProviderMock: AuthProvider, @unchecked Sendable {

    var credentialToReturn: JwtCredential?
    var errorToThrow: Error?
    var getCredentialCallCount = 0
    var invalidateCallCount = 0
    var registerCallCount = 0
    var lastTargetRequested: String?
    var lastTargetInvalidated: String?
    var lastTargetRegistered: String?

    func register(target: String) {
        registerCallCount += 1
        lastTargetRegistered = target
    }

    func getCredential(for target: String) async throws -> JwtCredential {
        getCredentialCallCount += 1
        lastTargetRequested = target
        if let error = errorToThrow {
            throw error
        }
        guard let credential = credentialToReturn else {
            fatalError("AuthProviderMock: credentialToReturn not set")
        }
        return credential
    }

    func invalidate(for target: String) {
        invalidateCallCount += 1
        lastTargetInvalidated = target
    }
}
