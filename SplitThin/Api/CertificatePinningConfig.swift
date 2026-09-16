//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Http

/// Called with `(host, reason)` when certificate pinning hard-fails for a connection.
/// `reason` describes why validation failed (e.g. "Key chain invalided", "Credential is not pinned").
public typealias CertificatePinningFailureHandler = @Sendable (String, String) -> Void

/// Called after every pinning challenge to a pinned host with `(host, status, reason)`.
/// - Warning: Invoked on a background thread. Dispatch to the main thread for UI work.
public typealias CertificatePinningStatusHandler = @Sendable (String, CertificatePinningStatus, String) -> Void

/// Errors surfaced while parsing pins at `CertificatePinningConfig.Builder.build()` time.
public enum CertificatePinningError: Error, CustomStringConvertible, Equatable {
    case invalidKeyHashFormat(host: String)
    case unsupportedAlgorithm(algorithm: String)
    case invalidKeyHashEncoding(host: String, algorithm: String)
    case emptyKeyHash(host: String, algorithm: String)
    case certificateParsingFailed(certificateName: String)

    public var description: String {
        switch self {
        case .invalidKeyHashFormat(let host):
            return "Invalid key hash for host \(host): expected format \"algorithm/base64Hash\""
        case .unsupportedAlgorithm(let algorithm):
            return "Key hash algorithm not supported: \(algorithm)"
        case .invalidKeyHashEncoding(let host, let algorithm):
            return "Key hash is not valid for host \(host) and algorithm \(algorithm) (expected base64-encoded digest: 32 bytes for sha256, 20 for sha1)"
        case .emptyKeyHash(let host, let algorithm):
            return "Key hash is empty for host \(host) and algorithm \(algorithm)"
        case .certificateParsingFailed(let name):
            return "Could not extract SPKI from certificate \(name).der"
        }
    }
}

/// Configuration for TLS certificate pinning.
///
/// Build it with ``builder()`` and attach it to ``SplitClientConfig`` via
/// `set(certificatePinning:)`. Pins are parsed and validated at ``Builder/build()``
/// time so the TLS handshake stays fast.
///
/// ### Usage
/// ```swift
/// let pinning = try CertificatePinningConfig.builder()
///     .addPin(host: "*.split.io", keyHash: "sha256/47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=")
///     .addPin(host: "auth.split.io", certificateName: "auth_split")
///     .set(failureHandler: { host, reason in print("pinning failed for \(host): \(reason)") })
///     .build()
///
/// let config = SplitClientConfig.builder()
///     .set(certificatePinning: pinning)
///     .build()
/// ```
public struct CertificatePinningConfig: Sendable {
    let pins: [CredentialPin]
    let failureHandler: CertificatePinningFailureHandler?
    let statusHandler: CertificatePinningStatusHandler?

    init(pins: [CredentialPin], failureHandler: CertificatePinningFailureHandler?, statusHandler: CertificatePinningStatusHandler?) {
        self.pins = pins
        self.failureHandler = failureHandler
        self.statusHandler = statusHandler
    }

    /// Creates a new builder for `CertificatePinningConfig`.
    public static func builder() -> Builder { Builder() }

    /// Builder for constructing a ``CertificatePinningConfig``.
    public final class Builder {

        private enum PinType { case certificate, keyHash }
        private struct PendingPin { let host: String; let value: String; let type: PinType }

        private var pendingPins: [PendingPin] = []
        private var failureHandler: CertificatePinningFailureHandler?
        private var statusHandler: CertificatePinningStatusHandler?

        // Visible for testing: bundle used to resolve certificate resources.
        var bundle: Bundle = .main

        /// Adds a certificate pin for `host`. The certificate must be a DER file named
        /// `certificateName.der` bundled in the app resources.
        @discardableResult
        public func addPin(host: String, certificateName: String) -> Builder {
            pendingPins.append(PendingPin(host: host, value: certificateName, type: .certificate))
            return self
        }

        /// Adds a public-key-hash pin for `host` in the form `"algorithm/base64Hash"`,
        /// e.g. `"sha256/47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="`.
        /// Supported algorithms: `sha256` (recommended), `sha1`.
        @discardableResult
        public func addPin(host: String, keyHash: String) -> Builder {
            pendingPins.append(PendingPin(host: host, value: keyHash, type: .keyHash))
            return self
        }

        /// Handler invoked with the `host` when pinning hard-fails for a connection.
        @discardableResult
        public func set(failureHandler: @escaping CertificatePinningFailureHandler) -> Builder {
            self.failureHandler = failureHandler
            return self
        }

        /// Handler invoked after every pinning challenge with `(host, status, reason)`.
        @discardableResult
        public func set(statusHandler: @escaping CertificatePinningStatusHandler) -> Builder {
            self.statusHandler = statusHandler
            return self
        }

        /// Parses every pin and returns the configuration.
        /// - Throws: ``CertificatePinningError`` if any pin cannot be parsed.
        public func build() throws -> CertificatePinningConfig {
            var pins = [CredentialPin]()
            for pending in pendingPins {
                switch pending.type {
                case .certificate:
                    pins.append(try parseCertificate(host: pending.host, name: pending.value))
                case .keyHash:
                    pins.append(try parseKeyHash(host: pending.host, hash: pending.value))
                }
            }
            return CertificatePinningConfig(pins: pins, failureHandler: failureHandler, statusHandler: statusHandler)
        }

        private func parseCertificate(host: String, name: String) throws -> CredentialPin {
            guard let spki = TlsCertificateParser.spki(from: name, bundle: bundle) else {
                throw CertificatePinningError.certificateParsingFailed(certificateName: name)
            }
            return CredentialPin(host: host, hash: AlgoHelper.computeHash(spki.data, algo: .sha256), algo: .sha256)
        }

        private func parseKeyHash(host: String, hash: String) throws -> CredentialPin {
            guard let separatorIndex = hash.firstIndex(of: "/") else {
                throw CertificatePinningError.invalidKeyHashFormat(host: host)
            }
            let algoName = String(hash[hash.startIndex..<separatorIndex])
            guard let algo = KeyHashAlgo(rawValue: algoName) else {
                throw CertificatePinningError.unsupportedAlgorithm(algorithm: algoName)
            }
            let encodedHash = String(hash[hash.index(after: separatorIndex)...])
            guard let dataHash = Data(base64Encoded: encodedHash) else {
                throw CertificatePinningError.invalidKeyHashEncoding(host: host, algorithm: algoName)
            }
            if dataHash.isEmpty {
                throw CertificatePinningError.emptyKeyHash(host: host, algorithm: algoName)
            }
            let expectedLength = algo == .sha256 ? 32 : 20
            if dataHash.count != expectedLength {
                throw CertificatePinningError.invalidKeyHashEncoding(host: host, algorithm: algoName)
            }
            return CredentialPin(host: host, hash: dataHash, algo: algo)
        }
    }
}
