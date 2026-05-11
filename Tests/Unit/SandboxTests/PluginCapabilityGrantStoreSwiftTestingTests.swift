// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginCapabilityGrantStoreSwiftTestingTests.swift - Plugin sandbox grant persistence coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Plugin capability grant store")
struct PluginCapabilityGrantStoreSwiftTestingTests {
    @Test("grant request exposes stable audit and UI data")
    func grantRequestExposesStableAuditData() {
        let request = PluginCapabilityRequest(
            pluginID: "local-plugin",
            capability: .networkClient,
            reason: "Fetch issue metadata",
            requestedAt: Date(timeIntervalSince1970: 42)
        )

        #expect(request.sandboxCapabilities == [.network])
        #expect(request.auditSubjectID == "plugin.local-plugin")
        #expect(request.auditOperation == "request plugin capability network-client")
    }

    @Test("store grants checks lists and revokes capability tuples")
    func storeGrantsChecksListsAndRevokesTuples() throws {
        let store = PluginCapabilityGrantStore(backend: MemoryPluginCapabilityGrantBackingStore())

        try store.grant(
            .networkClient,
            for: "local-plugin",
            reason: "User approved network access",
            grantedAt: Date(timeIntervalSince1970: 100)
        )
        try store.grant(
            .filesystemRead,
            for: "local-plugin",
            reason: "Read plugin resources",
            grantedAt: Date(timeIntervalSince1970: 101)
        )

        #expect(try store.isGranted(.networkClient, for: "local-plugin"))
        #expect(!store.isGrantedWithoutThrowing(.processSpawn, for: "local-plugin"))

        let grants = try store.grants(for: "local-plugin")
        #expect(grants.map(\.capability) == [.filesystemRead, .networkClient])
        #expect(grants[1].reason == "User approved network access")

        try store.revoke(.networkClient, for: "local-plugin")

        #expect(try !store.isGranted(.networkClient, for: "local-plugin"))
        #expect(try store.grants(for: "local-plugin").map(\.capability) == [.filesystemRead])
    }

    @Test("store lists grants independently per plugin")
    func storeListsGrantsIndependentlyPerPlugin() throws {
        let store = PluginCapabilityGrantStore(backend: MemoryPluginCapabilityGrantBackingStore())

        try store.grant(.networkClient, for: "alpha", reason: nil, grantedAt: Date(timeIntervalSince1970: 1))
        try store.grant(.filesystemWrite, for: "beta", reason: nil, grantedAt: Date(timeIntervalSince1970: 2))

        #expect(try store.grants(for: "alpha").map(\.capability) == [.networkClient])
        #expect(try store.grants(for: "beta").map(\.capability) == [.filesystemWrite])
        #expect(try store.allGrants().map(\.pluginID).sorted() == ["alpha", "beta"])
    }

    @Test("grant account encoding round trips plugin identifiers safely")
    func grantAccountEncodingRoundTripsPluginIdentifiersSafely() throws {
        let grant = PluginCapabilityGrant(
            pluginID: "plugin/with space:and:colon",
            capability: .filesystemWrite,
            reason: nil,
            grantedAt: Date(timeIntervalSince1970: 5)
        )

        let account = grant.keychainAccount
        let decoded = try #require(PluginCapabilityGrant.decodeKeychainAccount(account))

        #expect(decoded.pluginID == grant.pluginID)
        #expect(decoded.capability == grant.capability)
    }
}
