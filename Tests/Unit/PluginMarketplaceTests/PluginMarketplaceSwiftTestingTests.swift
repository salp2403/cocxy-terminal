// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginMarketplaceSwiftTestingTests.swift - Decentralized plugin marketplace coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Plugin marketplace")
struct PluginMarketplaceSwiftTestingTests {

    private func temporaryDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-plugin-marketplace-tests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("source store persists decentralized plugin sources")
    func sourceStorePersistsDecentralizedSources() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let storeURL = root.appendingPathComponent("sources.json")
        let store = PluginSourceStore(fileURL: storeURL)
        let sourceURL = try #require(URL(string: "https://github.com/example/cocxy-docker-helper.git"))

        try store.add(
            PluginSource(
                url: sourceURL,
                displayName: "Docker helpers"
            )
        )

        let reloaded = try PluginSourceStore(fileURL: storeURL).load()

        #expect(reloaded.count == 1)
        #expect(reloaded[0].url == sourceURL)
        #expect(reloaded[0].displayName == "Docker helpers")
    }

    @Test("source URL resolver accepts HTTPS, SSH shorthand, and local paths")
    func sourceURLResolverAcceptsSupportedForms() throws {
        #expect(PluginSourceURLResolver.resolve("https://github.com/example/plugin.git")?.scheme == "https")

        let sshURL = try #require(PluginSourceURLResolver.resolve("git@github.com:example/plugin.git"))
        #expect(sshURL.scheme == "ssh")
        #expect(sshURL.host == "github.com")
        #expect(sshURL.path == "/example/plugin.git")

        let fileURL = try #require(PluginSourceURLResolver.resolve("~/plugin"))
        #expect(fileURL.isFileURL)
    }

    @Test("marketplace manifest parses capabilities and optional signature")
    func manifestParsesMarketplaceFields() throws {
        let manifest = try PluginManifestParser.parse(
            content: """
            name = "Docker Helper"
            description = "Adds local Docker shortcuts"
            version = "1.2.3"
            author = "Cocxy"
            repository = "https://github.com/example/cocxy-docker-helper.git"
            license = "MIT"
            events = ["session-start", "command-complete"]
            capabilities = ["filesystem-read", "process-spawn"]
            """,
            directoryPath: "/tmp/cocxy-docker-helper",
            manifestFileName: PluginManifest.marketplaceManifestFileName
        )

        #expect(manifest.id == "cocxy-docker-helper")
        #expect(manifest.manifestFileName == PluginManifest.marketplaceManifestFileName)
        #expect(manifest.repositoryURL == "https://github.com/example/cocxy-docker-helper.git")
        #expect(manifest.capabilities == [.filesystemRead, .processSpawn])
        #expect(manifest.signature == nil)
    }

    @Test("validator allows unsigned plugins but reports unsigned status")
    func validatorAllowsUnsignedPlugin() throws {
        let manifest = PluginManifest(
            id: "unsigned-helper",
            name: "Unsigned Helper",
            description: "Local helper",
            version: "0.1.0",
            author: "Dev",
            minCocxyVersion: nil,
            events: [],
            directoryPath: "/tmp/unsigned-helper",
            manifestFileName: PluginManifest.marketplaceManifestFileName,
            capabilities: [.filesystemRead]
        )
        let sourceURL = try #require(URL(string: "https://github.com/example/unsigned-helper.git"))

        let report = try PluginValidator().validate(
            manifest: manifest,
            sourceURL: sourceURL,
            pluginDirectory: URL(fileURLWithPath: manifest.directoryPath)
        )

        #expect(report.isInstallable)
        #expect(report.signatureStatus == .unsignedAllowed)
        #expect(report.warnings.contains(.unsignedPlugin))
    }

    @Test("installer stages local repo and installed plugin loads next scan")
    @MainActor
    func installerRegistersPluginForNextScan() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Starter Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["session-start"]
        capabilities = ["environment-read"]
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )
        try "echo ok\n".write(
            to: repo.appendingPathComponent("on-session-start.sh"),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let installer = PluginInstaller(pluginsDirectory: pluginsDirectory)

        let receipt = try installer.install(from: repo)

        #expect(receipt.pluginID == "repo")
        #expect(receipt.signatureStatus == .unsignedAllowed)
        #expect(FileManager.default.fileExists(
            atPath: pluginsDirectory
                .appendingPathComponent("repo", isDirectory: true)
                .appendingPathComponent(PluginManifest.marketplaceManifestFileName)
                .path
        ))

        let manager = PluginManager(pluginsDirectory: pluginsDirectory.path)
        manager.scanPlugins()

        #expect(manager.plugins.count == 1)
        #expect(manager.plugins[0].id == "repo")
        #expect(manager.plugins[0].manifest.capabilities == [.environmentRead])
    }

    @Test("uninstall removes persisted enabled state")
    func uninstallRemovesPersistedEnabledState() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("stateful-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Stateful Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["session-start"]
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let installer = PluginInstaller(pluginsDirectory: pluginsDirectory)
        _ = try installer.install(from: repo)

        let stateURL = pluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugins.json")
        let enabledData = try JSONEncoder().encode(["stateful-plugin"])
        try enabledData.write(to: stateURL)

        try installer.uninstall(id: "stateful-plugin")

        let updatedData = try Data(contentsOf: stateURL)
        let updatedIDs = try JSONDecoder().decode([String].self, from: updatedData)

        #expect(updatedIDs.isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: pluginsDirectory
                .appendingPathComponent("stateful-plugin", isDirectory: true)
                .path
        ))
    }

    @Test("sandbox rejects scripts outside plugin directory")
    func sandboxRejectsScriptOutsidePluginDirectory() throws {
        let sandbox = PluginSandbox()

        #expect(throws: PluginSandboxError.self) {
            _ = try sandbox.makeExecutionPlan(
                scriptPath: "/tmp/other/on-session-start.sh",
                environment: ["COCXY_EVENT": "session-start"],
                pluginID: "safe-plugin",
                pluginDirectory: "/tmp/safe-plugin",
                capabilities: []
            )
        }
    }
}
