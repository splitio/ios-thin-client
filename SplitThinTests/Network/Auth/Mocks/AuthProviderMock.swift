import Foundation
@testable import SplitThin

final class AuthProviderMock: AuthProvider, @unchecked Sendable {

    var credentialToReturn: JwtCredential?
    var errorToThrow: Error?
    var getCredentialCallCount = 0
    var invalidateCallCount = 0
    var registerCallCount = 0
    var unregisterCallCount = 0
    var lastTargetRequested: String?
    var lastTargetInvalidated: String?
    var lastTargetRegistered: String?
    var lastTargetUnregistered: String?

    func register(target: String) {
        registerCallCount += 1
        lastTargetRegistered = target
    }

    func unregister(target: String) {
        unregisterCallCount += 1
        lastTargetUnregistered = target
    }

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

    func invalidate(for target: String) {
        invalidateCallCount += 1
        lastTargetInvalidated = target
    }
}
