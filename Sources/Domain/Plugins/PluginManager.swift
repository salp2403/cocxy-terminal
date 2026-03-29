// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginManager.swift - Lifecycle management for Cocxy plugins.

import Foundation
import Combine

// MARK: - Plugin State

/// Represents the runtime state of a loaded plugin.
struct PluginState: Identifiable, Equatable, Sendable {

    /// Unique identifier (matches the manifest ID / directory name).
    var id: String { manifest.id }

    /// The parsed manifest for this plugin.
    let manifest: PluginManifest

    /// Whether this plugin is currently enabled.
    var isEnabled: Bool

    /// When this plugin was last triggered (for display).
    var lastTriggeredAt: Date?
}

// MARK: - Plugin Manager Errors

/// Errors that can occur during plugin lifecycle operations.
enum PluginManagerError: Error, Equatable {
    case pluginNotFound(String)
    case alreadyEnabled(String)
    case alreadyDisabled(String)
    case directoryNotFound(String)
}

// MARK: - Plugin File System Protocol

/// Abstraction over filesystem operations for plugin management.
protocol PluginFileSystem: Sendable {
    func directoryExists(at path: String) -> Bool
    func listSubdirectories(at path: String) throws -> [String]
    func fileExists(at path: String) -> Bool
    func readFile(at path: String) throws -> String
    func writeFile(at path: String, contents: String) throws
}

// MARK: - Disk Plugin File System

/// Production filesystem implementation for plugin management.
final class DiskPluginFileSystem: PluginFileSystem {

    func directoryExists(at path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    func listSubdirectories(at path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
            .filter { name in
                var isDir: ObjCBool = false
                let fullPath = "\(path)/\(name)"
                return FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) && isDir.boolValue
            }
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func readFile(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    func writeFile(at path: String, contents: String) throws {
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - Plugin Manager

/// Manages the lifecycle of Cocxy plugins.
///
/// Plugins are stored as directories in `~/.config/cocxy/plugins/`.
/// Each directory must contain a `manifest.toml` file. Enabled/disabled
/// state is tracked in `~/.config/cocxy/plugins.json`.
///
/// ## Plugin Lifecycle
///
/// 1. **Discovery**: `scanPlugins()` reads all subdirectories and parses manifests.
/// 2. **Enable/Disable**: User toggles plugins on/off. State is persisted.
/// 3. **Event Dispatch**: When a terminal event occurs, enabled plugins with
///    matching event scripts are triggered via `PluginSandbox`.
@MainActor
final class PluginManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var plugins: [PluginState] = []

    // MARK: - Dependencies

    private let fileSystem: any PluginFileSystem
    private let pluginsDirectory: String
    private let stateFilePath: String
    private let sandbox: PluginSandbox

    // MARK: - Initialization

    init(
        fileSystem: any PluginFileSystem = DiskPluginFileSystem(),
        pluginsDirectory: String = {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return "\(home)/.config/cocxy/plugins"
        }(),
        sandbox: PluginSandbox = PluginSandbox()
    ) {
        self.fileSystem = fileSystem
        self.pluginsDirectory = pluginsDirectory
        self.stateFilePath = "\(pluginsDirectory)/../plugins.json"
        self.sandbox = sandbox
    }

    // MARK: - Discovery

    /// Scans the plugins directory and loads all valid plugin manifests.
    ///
    /// Merges discovered plugins with persisted enabled/disabled state.
    func scanPlugins() {
        guard fileSystem.directoryExists(at: pluginsDirectory) else {
            plugins = []
            return
        }

        let subdirectories: [String]
        do {
            subdirectories = try fileSystem.listSubdirectories(at: pluginsDirectory)
        } catch {
            plugins = []
            return
        }

        let enabledSet = loadEnabledState()

        plugins = subdirectories.compactMap { dirName -> PluginState? in
            let dirPath = "\(pluginsDirectory)/\(dirName)"
            let manifestPath = "\(dirPath)/manifest.toml"

            guard fileSystem.fileExists(at: manifestPath),
                  let content = try? fileSystem.readFile(at: manifestPath),
                  let manifest = try? PluginManifestParser.parse(
                      content: content,
                      directoryPath: dirPath
                  )
            else { return nil }

            return PluginState(
                manifest: manifest,
                isEnabled: enabledSet.contains(manifest.id)
            )
        }
    }

    // MARK: - Enable / Disable

    /// Enables a plugin by its ID.
    func enablePlugin(id: String) throws {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            throw PluginManagerError.pluginNotFound(id)
        }
        guard !plugins[index].isEnabled else {
            throw PluginManagerError.alreadyEnabled(id)
        }

        plugins[index].isEnabled = true
        saveEnabledState()
    }

    /// Disables a plugin by its ID.
    func disablePlugin(id: String) throws {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else {
            throw PluginManagerError.pluginNotFound(id)
        }
        guard plugins[index].isEnabled else {
            throw PluginManagerError.alreadyDisabled(id)
        }

        plugins[index].isEnabled = false
        saveEnabledState()
    }

    // MARK: - Event Dispatch

    /// Dispatches a terminal event to all enabled plugins that handle it.
    ///
    /// Each plugin's event script is executed in the sandbox with
    /// environment variables providing event context.
    ///
    /// - Parameters:
    ///   - event: The event type to dispatch.
    ///   - environment: Key-value pairs passed as env vars to scripts.
    func dispatchEvent(
        _ event: PluginEvent,
        environment: [String: String] = [:]
    ) {
        let enabledPlugins = plugins.filter { $0.isEnabled && $0.manifest.events.contains(event) }

        for plugin in enabledPlugins {
            let scriptPath = "\(plugin.manifest.directoryPath)/\(event.scriptName)"
            guard fileSystem.fileExists(at: scriptPath) else { continue }

            sandbox.execute(
                scriptPath: scriptPath,
                environment: environment,
                pluginID: plugin.id
            )

            // Update last triggered timestamp.
            if let index = plugins.firstIndex(where: { $0.id == plugin.id }) {
                plugins[index].lastTriggeredAt = Date()
            }
        }
    }

    // MARK: - Queries

    /// Returns all enabled plugins.
    var enabledPlugins: [PluginState] {
        plugins.filter(\.isEnabled)
    }

    /// Returns a plugin by its ID.
    func plugin(id: String) -> PluginState? {
        plugins.first { $0.id == id }
    }

    // MARK: - State Persistence

    /// Loads the set of enabled plugin IDs from disk.
    private func loadEnabledState() -> Set<String> {
        guard let content = try? fileSystem.readFile(at: stateFilePath),
              let data = content.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }

    /// Saves the set of enabled plugin IDs to disk.
    private func saveEnabledState() {
        let enabledIDs = plugins.filter(\.isEnabled).map(\.id).sorted()
        guard let data = try? JSONEncoder().encode(enabledIDs),
              let json = String(data: data, encoding: .utf8)
        else { return }
        try? fileSystem.writeFile(at: stateFilePath, contents: json)
    }
}
