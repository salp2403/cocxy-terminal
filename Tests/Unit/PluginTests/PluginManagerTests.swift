// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginManagerTests.swift - Tests for plugin lifecycle management.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - In-Memory Plugin File System

private final class InMemoryPluginFileSystem: PluginFileSystem, @unchecked Sendable {
    var files: [String: String] = [:]
    var directories: Set<String> = []

    func directoryExists(at path: String) -> Bool {
        directories.contains(path)
    }

    func listSubdirectories(at path: String) throws -> [String] {
        directories
            .filter { $0.hasPrefix(path + "/") && !$0.dropFirst(path.count + 1).contains("/") }
            .map { String($0.dropFirst(path.count + 1)) }
    }

    func fileExists(at path: String) -> Bool {
        files.keys.contains(path)
    }

    func readFile(at path: String) throws -> String {
        guard let content = files[path] else {
            throw NSError(domain: "test", code: 1)
        }
        return content
    }

    func writeFile(at path: String, contents: String) throws {
        files[path] = contents
    }
}

// MARK: - Plugin Manager Tests

@Suite("PluginManager")
struct PluginManagerTests {

    private func makeFS(plugins: [(id: String, manifest: String)]) -> (InMemoryPluginFileSystem, String) {
        let fs = InMemoryPluginFileSystem()
        let basePath = "/tmp/test-plugins"
        fs.directories.insert(basePath)

        for plugin in plugins {
            let pluginDir = "\(basePath)/\(plugin.id)"
            fs.directories.insert(pluginDir)
            fs.files["\(pluginDir)/manifest.toml"] = plugin.manifest
        }

        return (fs, basePath)
    }

    private let sampleManifest = """
    name = "Test Plugin"
    version = "1.0.0"
    author = "Dev"
    events = ["session-start", "agent-detected"]
    """

    // MARK: - Discovery

    @Test @MainActor func scanFindsPlugins() {
        let (fs, basePath) = makeFS(plugins: [
            (id: "plugin-a", manifest: sampleManifest),
            (id: "plugin-b", manifest: "name = \"Plugin B\"\nversion = \"0.1.0\""),
        ])

        let manager = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager.scanPlugins()

        #expect(manager.plugins.count == 2)
    }

    @Test @MainActor func scanSkipsInvalidManifests() {
        let (fs, basePath) = makeFS(plugins: [
            (id: "valid", manifest: sampleManifest),
            (id: "invalid", manifest: "this is not toml {{"),
        ])

        // The invalid manifest will still parse because our parser is lenient.
        // But one without "name" will fail:
        fs.files["\(basePath)/no-name/manifest.toml"] = "version = \"1.0.0\""
        fs.directories.insert("\(basePath)/no-name")

        let manager = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager.scanPlugins()

        // "valid" and "invalid" parse (invalid has no name field? let's check)
        // Actually "invalid" has "this is not toml {{" which won't parse "name" key
        // So only "valid" should parse successfully
        #expect(manager.plugins.count == 1)
        #expect(manager.plugins[0].id == "valid")
    }

    @Test @MainActor func scanWithEmptyDirectory() {
        let fs = InMemoryPluginFileSystem()
        let basePath = "/tmp/empty-plugins"
        fs.directories.insert(basePath)

        let manager = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager.scanPlugins()

        #expect(manager.plugins.isEmpty)
    }

    @Test @MainActor func scanWithNonexistentDirectory() {
        let fs = InMemoryPluginFileSystem()

        let manager = PluginManager(fileSystem: fs, pluginsDirectory: "/nonexistent")
        manager.scanPlugins()

        #expect(manager.plugins.isEmpty)
    }

    // MARK: - Enable / Disable

    @Test @MainActor func enablePlugin() throws {
        let (fs, basePath) = makeFS(plugins: [
            (id: "test-plugin", manifest: sampleManifest),
        ])

        let manager = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager.scanPlugins()

        #expect(manager.plugins[0].isEnabled == false)

        try manager.enablePlugin(id: "test-plugin")

        #expect(manager.plugins[0].isEnabled == true)
    }

    @Test @MainActor func disablePlugin() throws {
        let (fs, basePath) = makeFS(plugins: [
            (id: "test-plugin", manifest: sampleManifest),
        ])

        let manager = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager.scanPlugins()
        try manager.enablePlugin(id: "test-plugin")

        try manager.disablePlugin(id: "test-plugin")

        #expect(manager.plugins[0].isEnabled == false)
    }

    @Test @MainActor func enableNonexistentPluginThrows() {
        let (fs, basePath) = makeFS(plugins: [])

        let manager = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager.scanPlugins()

        #expect(throws: PluginManagerError.self) {
            try manager.enablePlugin(id: "ghost")
        }
    }

    @Test @MainActor func enableAlreadyEnabledThrows() throws {
        let (fs, basePath) = makeFS(plugins: [
            (id: "test-plugin", manifest: sampleManifest),
        ])

        let manager = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager.scanPlugins()
        try manager.enablePlugin(id: "test-plugin")

        #expect(throws: PluginManagerError.self) {
            try manager.enablePlugin(id: "test-plugin")
        }
    }

    @Test @MainActor func disableAlreadyDisabledThrows() {
        let (fs, basePath) = makeFS(plugins: [
            (id: "test-plugin", manifest: sampleManifest),
        ])

        let manager = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager.scanPlugins()

        #expect(throws: PluginManagerError.self) {
            try manager.disablePlugin(id: "test-plugin")
        }
    }

    // MARK: - Queries

    @Test @MainActor func enabledPluginsFilter() throws {
        let (fs, basePath) = makeFS(plugins: [
            (id: "enabled-one", manifest: sampleManifest),
            (id: "disabled-one", manifest: "name = \"Disabled\"\nversion = \"1.0.0\""),
        ])

        let manager = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager.scanPlugins()
        try manager.enablePlugin(id: "enabled-one")

        #expect(manager.enabledPlugins.count == 1)
        #expect(manager.enabledPlugins[0].id == "enabled-one")
    }

    @Test @MainActor func pluginByID() {
        let (fs, basePath) = makeFS(plugins: [
            (id: "find-me", manifest: sampleManifest),
        ])

        let manager = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager.scanPlugins()

        #expect(manager.plugin(id: "find-me") != nil)
        #expect(manager.plugin(id: "find-me")?.manifest.name == "Test Plugin")
        #expect(manager.plugin(id: "ghost") == nil)
    }

    // MARK: - State Persistence

    @Test @MainActor func enabledStatePersists() throws {
        let (fs, basePath) = makeFS(plugins: [
            (id: "persist-me", manifest: sampleManifest),
        ])

        let manager1 = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager1.scanPlugins()
        try manager1.enablePlugin(id: "persist-me")

        // Create a new manager instance (simulates app restart).
        let manager2 = PluginManager(fileSystem: fs, pluginsDirectory: basePath)
        manager2.scanPlugins()

        #expect(manager2.plugins[0].isEnabled == true)
    }

    // MARK: - Plugin State Model

    @Test func pluginStateIdentifier() {
        let manifest = PluginManifest(
            id: "test-id",
            name: "Test",
            description: "A test plugin",
            version: "1.0.0",
            author: "Dev",
            minCocxyVersion: nil,
            events: [],
            directoryPath: "/tmp/test"
        )

        let state = PluginState(manifest: manifest, isEnabled: false)

        #expect(state.id == "test-id")
        #expect(state.isEnabled == false)
        #expect(state.lastTriggeredAt == nil)
    }
}
