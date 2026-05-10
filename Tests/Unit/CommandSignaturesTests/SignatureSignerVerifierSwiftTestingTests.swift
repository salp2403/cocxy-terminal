// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCommandSignatures

@Suite("Signature signer and verifier")
struct SignatureSignerVerifierSwiftTestingTests {
    @Test("valid signatures verify against the trusted public key")
    func validSignaturesVerifyAgainstTrustedPublicKey() throws {
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let payload = Data("template-body".utf8)
        let artifact = try SignatureSigner().sign(
            payload: payload,
            author: "Cocxy",
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let result = SignatureVerifier().verify(
            payload: payload,
            artifact: artifact,
            publicKey: keyPair.publicKey
        )

        #expect(result == .valid)
        #expect(artifact.payloadSHA256 == SignatureDigest.sha256Base64(payload))
    }

    @Test("tampered payloads fail before signature verification")
    func tamperedPayloadsFailBeforeSignatureVerification() throws {
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let artifact = try SignatureSigner().sign(
            payload: Data("safe".utf8),
            author: "Cocxy",
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let result = SignatureVerifier().verify(
            payload: Data("changed".utf8),
            artifact: artifact,
            publicKey: keyPair.publicKey
        )

        #expect(result == .payloadDigestMismatch)
    }

    @Test("wrong public keys reject signatures")
    func wrongPublicKeysRejectSignatures() throws {
        let signerKey = try SignatureKeyPair.generate(author: "Cocxy")
        let otherKey = try SignatureKeyPair.generate(author: "Other")
        let payload = Data("macro".utf8)
        let artifact = try SignatureSigner().sign(
            payload: payload,
            author: "Cocxy",
            keyPair: signerKey,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let result = SignatureVerifier().verify(
            payload: payload,
            artifact: artifact,
            publicKey: otherKey.publicKey
        )

        #expect(result == .keyMismatch)
    }

    @Test("metadata tampering invalidates the signature")
    func metadataTamperingInvalidatesSignature() throws {
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let payload = Data("plugin".utf8)
        let artifact = try SignatureSigner().sign(
            payload: payload,
            author: "Cocxy",
            keyPair: keyPair,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let tampered = SignedArtifact(
            algorithm: artifact.algorithm,
            keyID: artifact.keyID,
            author: "Mallory",
            timestamp: artifact.timestamp,
            payloadSHA256: artifact.payloadSHA256,
            signature: artifact.signature
        )

        let result = SignatureVerifier().verify(
            payload: payload,
            artifact: tampered,
            publicKey: keyPair.publicKey
        )

        #expect(result == .invalidSignature)
    }
}
