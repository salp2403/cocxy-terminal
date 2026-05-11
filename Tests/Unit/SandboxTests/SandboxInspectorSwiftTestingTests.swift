// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SandboxInspectorSwiftTestingTests.swift - Sandbox inspector view-model coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Sandbox inspector")
struct SandboxInspectorSwiftTestingTests {
    @MainActor
    @Test("view model loads grants audit entries and revokes grants")
    func viewModelLoadsAuditAndRevokesGrants() throws {
        let grantBackend = MemoryPluginCapabilityGrantBackingStore()
        let grantStore = PluginCapabilityGrantStore(backend: grantBackend)
        try grantStore.grant(
            .networkClient,
            for: "sample-plugin",
            reason: "User approved network",
            grantedAt: Date(timeIntervalSince1970: 100)
        )

        let auditURL = temporaryAuditLogURL()
        defer { try? FileManager.default.removeItem(at: auditURL.deletingLastPathComponent()) }

        let auditLog = SandboxAuditLog(fileURL: auditURL)
        try auditLog.append(SandboxAuditEntry(
            timestamp: Date(timeIntervalSince1970: 101),
            subjectID: "plugin.sample-plugin",
            subjectKind: .plugin,
            operation: "request plugin capability network-client",
            capability: .network,
            decision: .granted,
            detail: "User approved network"
        ))

        let viewModel = SandboxInspectorViewModel(
            grantStore: grantStore,
            auditLog: auditLog,
            localizer: AppLocalizer(languagePreference: .english)
        )

        #expect(viewModel.grants.count == 1)
        #expect(viewModel.grants.first?.pluginID == "sample-plugin")
        #expect(viewModel.grants.first?.capability == .networkClient)
        #expect(viewModel.grants.first?.reason == "User approved network")
        #expect(viewModel.auditEntries.count == 1)
        #expect(viewModel.auditEntries.first?.subjectID == "plugin.sample-plugin")

        let row = try #require(viewModel.grants.first)
        viewModel.revoke(row)

        #expect(viewModel.grants.isEmpty)
        #expect(try !grantStore.isGranted(.networkClient, for: "sample-plugin"))
        #expect(viewModel.statusMessage == "Revoked network-client from sample-plugin.")
    }

    @MainActor
    @Test("localized capability uses bundled Spanish resources")
    func localizedCapabilityUsesSpanishResources() throws {
        let bundle = try #require(localizationBundle())
        let viewModel = SandboxInspectorViewModel(
            grantStore: PluginCapabilityGrantStore(backend: MemoryPluginCapabilityGrantBackingStore()),
            auditLog: SandboxAuditLog(fileURL: temporaryAuditLogURL()),
            localizer: AppLocalizer(languagePreference: .spanish, bundle: bundle)
        )

        #expect(viewModel.localized("sandboxInspector.revoke", fallback: "Revoke") == "Revocar")
        #expect(viewModel.localizedCapability(.networkClient) == "Cliente de red")
    }

    private func temporaryAuditLogURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-sandbox-inspector-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("audit.log")
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
