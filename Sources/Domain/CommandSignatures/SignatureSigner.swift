// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public enum SignatureSigningError: Error, Equatable, Sendable {
    case missingPrivateKey(String)
}

public struct SignatureSigner: Sendable {
    public init() {}

    public func sign(
        payload: Data,
        author: String,
        keyPair: SignatureKeyPair,
        timestamp: Date = Date()
    ) throws -> SignedArtifact {
        let payloadSHA256 = SignatureDigest.sha256Base64(payload)
        let canonicalPayload = SignatureCanonicalPayload.data(
            algorithm: keyPair.algorithm,
            keyID: keyPair.keyID,
            author: author,
            timestamp: timestamp,
            payloadSHA256: payloadSHA256
        )
        let signature = try keyPair.privateSigningKey()
            .signature(for: canonicalPayload)
            .base64EncodedString()

        return SignedArtifact(
            algorithm: keyPair.algorithm,
            keyID: keyPair.keyID,
            author: author,
            timestamp: timestamp,
            payloadSHA256: payloadSHA256,
            signature: signature
        )
    }
}
