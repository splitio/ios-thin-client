//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Security
import Http
@testable import SplitThin

/// DER test certificates and public keys.
/// Pairs (cert, public key) belong to the same key, so the SPKI hash extracted from the
/// certificate equals the hash of the corresponding public-key DER.
enum TestCerts {
    static let appleEcCert = "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"
    static let appleEcPub = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEixU7dO9enXNgTzkqg32dzEFhGlAx6IR41RmDpHPF2vVLtbw5hseJ9iZAue/tColHXBFRCbp6M3h6Y9Gvzq/A3A=="
    static let rsa2048Cert = "MIIDOTCCAiGgAwIBAgIUMW6yWj/PhfuXstPPxj2XA8D1QqowDQYJKoZIhvcNAQELBQAwRTELMAkGA1UEBhMCQVUxEzARBgNVBAgMClNvbWUtU3RhdGUxITAfBgNVBAoMGEludGVybmV0IFdpZGdpdHMgUHR5IEx0ZDAeFw0yNDA2MTQxODQ0MTBaFw0yNTA2MTQxODQ0MTBaMEUxCzAJBgNVBAYTAkFVMRMwEQYDVQQIDApTb21lLVN0YXRlMSEwHwYDVQQKDBhJbnRlcm5ldCBXaWRnaXRzIFB0eSBMdGQwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDCTcKRDrnTPhh7huuRdvU/kFy4cgrLpipX83nZmoPnX/NWvkR3mvaqNvla1+BIh+iOZgF4EsRIid6n0kgGGIxkLEX/lj9jKXWSdm7UtegVi2xu9o1OyenPKw0WMBvwW/nrxZ6DBbDxHnP6LXXOIHEbxW5McwQAGn0ebyqWJ2wAbcsRc/J1h2xwCCRGRASp3ftiXrP3oAcOKD+ubLUHukoPTRFCC2boAiKAoYqb10niHkSWKiog2i+ybzvs5sCWRYjHCHUO0EzBoilMTop78Q515qddsvcq+Kyl1mRgOx9g2kTU7Szz4KAnqSb0rZ+RAZQQIcawOjklfQWDLUtqrjpXAgMBAAGjITAfMB0GA1UdDgQWBBSclON+dkMe+uAxjd+M8+UEKuIPqzANBgkqhkiG9w0BAQsFAAOCAQEAHHJ/ieFY4hJ1Qzpu0KzRUs1ASP2twQb/Ps7A6UMWFDMpkbvRwKvuwbckjl0hPVHPG6Erc099DSX6rkpEiGK5RSZLE6mt8YF0/WdaKEO6SGuqBPwv1pLoC7BTSJHFy6UpldxE/vOYciJqTgwkRsQVPOUWgDNh6iBxU4zQRD2DI1gwIkRze+cne3PphSqyK/MW4pyTC2mAkcDDZhRstpU2EArWJv2F9WkxHwz+yyqh3yKDexiNJfC0c8cJDymDRntiUWovzT4Jgkhzh0Ofc0YTBZMhCTODUlzV6FV6C7KFBf9NXg7yGs/vAuWMtdrEzuW9Ws4MvKZJvgyREeyhOz/+ZA=="
    static let rsa2048Pub = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwk3CkQ650z4Ye4brkXb1P5BcuHIKy6YqV/N52ZqD51/zVr5Ed5r2qjb5WtfgSIfojmYBeBLESInep9JIBhiMZCxF/5Y/Yyl1knZu1LXoFYtsbvaNTsnpzysNFjAb8Fv568WegwWw8R5z+i11ziBxG8VuTHMEABp9Hm8qlidsAG3LEXPydYdscAgkRkQEqd37Yl6z96AHDig/rmy1B7pKD00RQgtm6AIigKGKm9dJ4h5ElioqINovsm877ObAlkWIxwh1DtBMwaIpTE6Ke/EOdeanXbL3KvispdZkYDsfYNpE1O0s8+CgJ6km9K2fkQGUECHGsDo5JX0Fgy1Laq46VwIDAQAB"

    private static let byName: [String: String] = [
        "apple_ec_cert": appleEcCert,
        "apple_ec_pub": appleEcPub,
        "rsa_2048_cert": rsa2048Cert,
        "rsa_2048_pub": rsa2048Pub,
    ]

    static func data(named name: String) -> Data? {
        guard let b64 = byName[name] else { return nil }
        return Data(base64Encoded: b64)
    }

    /// Materializes the given certificates as `<name>.der` files into a temp directory and
    /// returns a `Bundle` pointing at it, so code that loads certs via `Bundle` can be tested
    static func makeBundle(names: [String]) -> Bundle {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("certs-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names {
            if let data = data(named: name) {
                try? data.write(to: dir.appendingPathComponent("\(name).der"))
            }
        }
        return Bundle(path: dir.path) ?? .main
    }
}

/// Fabricates `URLAuthenticationChallenge` values backed by real DER certificates so the
/// pinning logic can be exercised without opening a socket. Adapted from ios-client.
final class SecurityHelper {

    func certificateFromFile(name: String) -> SecCertificate? {
        guard let data = TestCerts.data(named: name) as NSData? else { return nil }
        return SecCertificateCreateWithData(nil, data)
    }

    func createServerTrust(certName: String) -> SecTrust? {
        guard let certificate = certificateFromFile(name: certName) else { return nil }
        var trust: SecTrust?
        SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust)
        return trust
    }

    func createProtectionSpace(host: String, certName: String) -> URLProtectionSpace? {
        guard let serverTrust = createServerTrust(certName: certName) else { return nil }
        return ProtectionSpaceMock(host: host, secTrust: serverTrust)
    }

    func createAuthChallenge(host: String, certName: String) -> URLAuthenticationChallenge? {
        guard let protectionSpace = createProtectionSpace(host: host, certName: certName) else { return nil }
        return URLAuthenticationChallenge(protectionSpace: protectionSpace, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: ChallengeSenderMock())
    }

    func createInvalidChallenge(authMethod: String) -> URLAuthenticationChallenge {
        URLAuthenticationChallenge(protectionSpace: ProtectionSpaceMock(authMethod: authMethod), proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: ChallengeSenderMock())
    }

    func createChallengeWithoutSecTrust() -> URLAuthenticationChallenge {
        URLAuthenticationChallenge(protectionSpace: ProtectionSpaceMock(authMethod: NSURLAuthenticationMethodServerTrust), proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: ChallengeSenderMock())
    }

    /// Computes the SPKI hash of a bundled public-key DER, matching what the pin checker compares against.
    func hashedKey(keyName: String, algo: KeyHashAlgo) -> Data {
        guard let keyData = TestCerts.data(named: keyName) else { return Data() }
        return AlgoHelper.computeHash(keyData, algo: algo)
    }
}

final class ChallengeSenderMock: NSObject, URLAuthenticationChallengeSender, @unchecked Sendable {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}

final class ProtectionSpaceMock: URLProtectionSpace, @unchecked Sendable {

    private var serverTrustMock: SecTrust?

    init(host: String, secTrust: SecTrust) {
        self.serverTrustMock = secTrust
        super.init(host: host, port: 443, protocol: NSURLProtectionSpaceHTTPS, realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust)
    }

    init(host: String = "www.testhost.com", authProtocol: String = NSURLProtectionSpaceHTTPS, authMethod: String = NSURLAuthenticationMethodServerTrust) {
        super.init(host: host, port: 443, protocol: authProtocol, realm: nil, authenticationMethod: authMethod)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var serverTrust: SecTrust? { serverTrustMock }
}
