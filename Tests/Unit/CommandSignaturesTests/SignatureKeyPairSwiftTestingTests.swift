// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCommandSignatures

@Suite("Signature key pairs")
struct SignatureKeyPairSwiftTestingTests {
    @Test("generated keys expose stable public fingerprints")
    func generatedKeysExposeStablePublicFingerprints() throws {
        let keyPair = try SignatureKeyPair.generate(author: "Said")

        #expect(keyPair.algorithm == .ed25519)
        #expect(keyPair.author == "Said")
        #expect(keyPair.keyID.count == 16)
        #expect(!keyPair.publicKeyBase64.isEmpty)
        #expect(keyPair.hasPrivateKey)
        #expect(keyPair.publicOnly().keyID == keyPair.keyID)
        #expect(!keyPair.publicOnly().hasPrivateKey)
    }

    @Test("key id is derived from public key only")
    func keyIDIsDerivedFromPublicKeyOnly() throws {
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")
        let restoredPublicKey = try SignaturePublicKey(
            algorithm: keyPair.algorithm,
            keyID: keyPair.keyID,
            author: keyPair.author,
            rawRepresentation: keyPair.publicKeyRawRepresentation
        )

        #expect(restoredPublicKey.keyID == keyPair.keyID)
        #expect(restoredPublicKey.fingerprint == keyPair.fingerprint)
    }

    @Test("public-only keys cannot sign payloads")
    func publicOnlyKeysCannotSignPayloads() throws {
        let publicOnly = try SignatureKeyPair.generate(author: "Cocxy").publicOnly()
        let signer = SignatureSigner()

        #expect(throws: SignatureSigningError.missingPrivateKey(publicOnly.keyID)) {
            _ = try signer.sign(
                payload: Data("payload".utf8),
                author: "Cocxy",
                keyPair: publicOnly,
                timestamp: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }
    }
}
