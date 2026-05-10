// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CryptoKit
import Foundation

public enum SignatureVerificationResult: Equatable, Sendable {
    case valid
    case unsupportedAlgorithm
    case keyMismatch
    case payloadDigestMismatch
    case invalidSignature
    case malformedSignature
    case malformedPublicKey
}

public struct SignatureVerifier: Sendable {
    public init() {}

    public func verify(
        payload: Data,
        artifact: SignedArtifact,
        publicKey: SignaturePublicKey
    ) -> SignatureVerificationResult {
        guard artifact.algorithm == .ed25519, publicKey.algorithm == .ed25519 else {
            return .unsupportedAlgorithm
        }
        guard artifact.keyID == publicKey.keyID else {
            return .keyMismatch
        }
        guard SignatureDigest.sha256Base64(payload) == artifact.payloadSHA256 else {
            return .payloadDigestMismatch
        }
        guard let signature = Data(base64Encoded: artifact.signature) else {
            return .malformedSignature
        }
        let canonicalPayload = SignatureCanonicalPayload.data(
            algorithm: artifact.algorithm,
            keyID: artifact.keyID,
            author: artifact.author,
            timestamp: artifact.timestamp,
            payloadSHA256: artifact.payloadSHA256
        )
        do {
            let signingKey = try Curve25519.Signing.PublicKey(
                rawRepresentation: publicKey.rawRepresentation
            )
            return signingKey.isValidSignature(signature, for: canonicalPayload)
                ? .valid
                : .invalidSignature
        } catch {
            return .malformedPublicKey
        }
    }
}
