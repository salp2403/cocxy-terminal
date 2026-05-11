// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PluginMarketplaceViewModel")
struct PluginMarketplaceViewModelSwiftTestingTests {

    private func temporaryDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-plugin-marketplace-viewmodel-tests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("add source and install local plugin refreshes state")
    @MainActor
    func addSourceAndInstallRefreshesState() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("sample-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Sample Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["session-start"]
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let manager = PluginManager(pluginsDirectory: pluginsDirectory.path)
        let viewModel = PluginMarketplaceViewModel(
            sourceStore: PluginSourceStore(fileURL: root.appendingPathComponent("sources.json")),
            installer: PluginInstaller(pluginsDirectory: pluginsDirectory),
            pluginManager: manager,
            bundledCatalog: BundledPluginCatalog(pluginsDirectory: nil)
        )

        viewModel.sourceURLText = repo.path
        viewModel.sourceDisplayName = "Local sample"
        try viewModel.addSource()

        #expect(viewModel.sources.count == 1)
        #expect(viewModel.sources[0].displayName == "Local sample")

        viewModel.installURLText = repo.path
        try viewModel.installPlugin(replaceExisting: false)

        #expect(viewModel.plugins.count == 1)
        #expect(viewModel.plugins[0].id == "sample-plugin")
        #expect(viewModel.signatureStatus(for: "sample-plugin") == .unsignedAllowed)
        #expect(viewModel.statusMessage == "Installed sample-plugin.")
    }

    @Test("plugin marketplace exposes signature badge labels")
    @MainActor
    func pluginMarketplaceExposesSignatureBadgeLabels() {
        let localizer = AppLocalizer(languagePreference: .english)

        #expect(PluginSignatureStatus.verified.localizedBadgeTitle(using: localizer) == "Verified")
        #expect(PluginSignatureStatus.unsignedAllowed.localizedBadgeTitle(using: localizer) == "Unsigned")
        #expect(PluginSignatureStatus.presentButUnverified.localizedBadgeTitle(using: localizer) == "Unverified")
        #expect(PluginSignatureStatus.invalid.localizedBadgeTitle(using: localizer) == "Invalid signature")
    }

    @Test("Spanish localizer translates plugin signature badge labels")
    @MainActor
    func spanishLocalizerTranslatesPluginSignatureBadgeLabels() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(PluginSignatureStatus.verified.localizedBadgeTitle(using: spanish) == "Verificado")
        #expect(PluginSignatureStatus.unsignedAllowed.localizedBadgeTitle(using: spanish) == "Sin firma")
        #expect(PluginSignatureStatus.presentButUnverified.localizedBadgeTitle(using: spanish) == "Sin verificar")
        #expect(PluginSignatureStatus.invalid.localizedBadgeTitle(using: spanish) == "Firma inválida")
    }

    @Test("install bundled plugin refreshes installed state")
    @MainActor
    func installBundledPluginRefreshesState() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundled = root.appendingPathComponent("bundled", isDirectory: true)
        let plugin = bundled.appendingPathComponent("cocxy-bundled", isDirectory: true)
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        try """
        name = "Bundled Plugin"
        version = "1.0.0"
        author = "Cocxy"
        events = ["session-start"]
        capabilities = ["environment-read"]
        """.write(
            to: plugin.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let manager = PluginManager(pluginsDirectory: pluginsDirectory.path)
        let viewModel = PluginMarketplaceViewModel(
            sourceStore: PluginSourceStore(fileURL: root.appendingPathComponent("sources.json")),
            installer: PluginInstaller(pluginsDirectory: pluginsDirectory),
            pluginManager: manager,
            bundledCatalog: BundledPluginCatalog(pluginsDirectory: bundled)
        )

        #expect(viewModel.bundledPlugins.count == 1)

        try viewModel.installBundledPlugin(id: "cocxy-bundled", replaceExisting: false)

        #expect(viewModel.plugins.count == 1)
        #expect(viewModel.plugins[0].id == "cocxy-bundled")
        #expect(viewModel.statusMessage == "Installed cocxy-bundled.")
    }

    @Test("enabling plugin with unapproved capabilities opens approval request")
    @MainActor
    func enablingPluginWithUnapprovedCapabilitiesOpensApprovalRequest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("sandboxed-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Sandboxed Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["session-start"]
        capabilities = ["environment-read", "network-client"]
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let grantStore = PluginCapabilityGrantStore(backend: MemoryPluginCapabilityGrantBackingStore())
        let manager = PluginManager(pluginsDirectory: pluginsDirectory.path) { pluginID in
            Set(((try? grantStore.grants(for: pluginID)) ?? []).map(\.capability))
        }
        let viewModel = PluginMarketplaceViewModel(
            sourceStore: PluginSourceStore(fileURL: root.appendingPathComponent("sources.json")),
            installer: PluginInstaller(pluginsDirectory: pluginsDirectory),
            pluginManager: manager,
            bundledCatalog: BundledPluginCatalog(pluginsDirectory: nil),
            grantStore: grantStore
        )

        viewModel.installURLText = repo.path
        try viewModel.installPlugin(replaceExisting: false)
        try viewModel.setPlugin("sandboxed-plugin", enabled: true)

        #expect(viewModel.pendingCapabilityRequest?.pluginID == "sandboxed-plugin")
        #expect(viewModel.pendingCapabilityRequest?.capabilities == [.environmentRead, .networkClient])
        #expect(viewModel.plugins.first?.isEnabled == false)

        try viewModel.approvePendingCapabilityRequest()

        #expect(viewModel.pendingCapabilityRequest == nil)
        #expect(viewModel.plugins.first?.isEnabled == true)
        #expect(try grantStore.isGranted(.environmentRead, for: "sandboxed-plugin"))
        #expect(try grantStore.isGranted(.networkClient, for: "sandboxed-plugin"))
    }

    @Test("Spanish localizer updates plugin marketplace statuses")
    @MainActor
    func spanishLocalizerUpdatesPluginMarketplaceStatuses() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let viewModel = PluginMarketplaceViewModel(
            sourceStore: PluginSourceStore(fileURL: root.appendingPathComponent("sources.json")),
            installer: PluginInstaller(pluginsDirectory: root.appendingPathComponent("plugins", isDirectory: true)),
            pluginManager: PluginManager(pluginsDirectory: root.appendingPathComponent("plugins", isDirectory: true).path),
            bundledCatalog: BundledPluginCatalog(pluginsDirectory: nil),
            localizer: spanish
        )

        viewModel.checkForPluginUpdates()

        #expect(viewModel.statusMessage == "No se encontraron actualizaciones.")
        #expect(
            viewModel.localizedErrorDescription(PluginMarketplaceViewModelError.missingURL)
                == "Ingresa una URL de plugin o una ruta local."
        )

        viewModel.updateLocalizer(AppLocalizer(languagePreference: .english, bundle: bundle))

        #expect(viewModel.statusMessage == "No updates found.")
    }

    @Test("plugin marketplace keeps a stable top scroll anchor")
    func pluginMarketplaceViewKeepsStableTopScrollAnchor() {
        #expect(PluginMarketplaceView.initialScrollAnchorID == "plugin-marketplace-top")
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
