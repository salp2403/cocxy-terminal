// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ICloudSyncSecretsSwiftTestingTests.swift - Local secret contracts for iCloud Sync.

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
}
