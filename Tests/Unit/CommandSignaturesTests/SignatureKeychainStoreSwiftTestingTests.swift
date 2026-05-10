// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCommandSignatures

@Suite("Signature keychain store")
struct SignatureKeychainStoreSwiftTestingTests {
    @Test("store saves loads lists and deletes key pairs")
    func storeSavesLoadsListsAndDeletesKeyPairs() throws {
        let backend = MemorySignatureKeyValueStore()
        let store = SignatureKeychainStore(backend: backend)
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy")

        try store.save(keyPair)
        #expect(try store.load(keyID: keyPair.keyID) == keyPair)
        #expect(try store.listKeyIDs() == [keyPair.keyID])

        try store.delete(keyID: keyPair.keyID)
        #expect(try store.load(keyID: keyPair.keyID) == nil)
        #expect(try store.listKeyIDs().isEmpty)
    }

    @Test("store rejects public-only keys")
    func storeRejectsPublicOnlyKeys() throws {
        let store = SignatureKeychainStore(backend: MemorySignatureKeyValueStore())
        let keyPair = try SignatureKeyPair.generate(author: "Cocxy").publicOnly()

        #expect(throws: SignatureKeyStoreError.privateKeyRequired(keyPair.keyID)) {
            try store.save(keyPair)
        }
    }
}
