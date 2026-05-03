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
        #expect(viewModel.statusMessage == "Installed sample-plugin.")
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
}
