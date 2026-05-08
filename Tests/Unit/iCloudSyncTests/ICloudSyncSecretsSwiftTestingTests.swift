// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ICloudSyncSecretsSwiftTestingTests.swift - Local secret contracts for iCloud Sync.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("iCloud Sync secrets")
struct ICloudSyncSecretsSwiftTestingTests {
    @Test("master password saves loads trims and deletes locally")
    func masterPasswordSaveLoadTrimAndDelete() throws {
        let secrets = ICloudSyncSecrets(store: InMemoryICloudSyncSecretStore())

        try secrets.saveMasterPassword("  sync-password\n")

        #expect(try secrets.masterPassword() == "sync-password")
        #expect(try secrets.hasMasterPassword())

        try secrets.deleteMasterPassword()

        #expect(try secrets.masterPassword() == nil)
        #expect(try !secrets.hasMasterPassword())
    }

    @Test("master password rejects empty values")
    func masterPasswordRejectsEmptyValues() {
        let secrets = ICloudSyncSecrets(store: InMemoryICloudSyncSecretStore())

        #expect(throws: ICloudSyncSecretError.emptyMasterPassword) {
            try secrets.saveMasterPassword(" \n\t ")
        }
    }

    @Test("keychain store saves replaces loads and deletes generic secrets")
    func keychainStoreSavesReplacesLoadsAndDeletesGenericSecrets() throws {
        let store = KeychainICloudSyncSecretStore()
        let account = "icloud-sync-secret-test-\(UUID().uuidString)"
        defer { try? store.deleteSecret(account: account) }

        try store.deleteSecret(account: account)
        #expect(try store.secret(account: account) == nil)

        try store.saveSecret("first-password", account: account)
        #expect(try store.secret(account: account) == "first-password")

        try store.saveSecret("replacement-password", account: account)
        #expect(try store.secret(account: account) == "replacement-password")

        try store.deleteSecret(account: account)
        #expect(try store.secret(account: account) == nil)
    }
}
