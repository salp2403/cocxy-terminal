// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginManager.swift - Lifecycle management for Cocxy plugins.

import Combine
import Darwin
import Foundation

extension Notification.Name {
    static let cocxyPluginAuthorizationDidReset = Notification.Name(
        "dev.cocxy.plugin-authorization-did-reset"
    )
}

private final class PluginAuthorizationResetObservation: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

/// Identifies one installed directory generation without following a replaced
/// registry entry. Cooperative installs use an atomic root swap, so any
/// replacement changes this identity before a queued event can launch.
private struct PluginInstallationIdentity: Equatable, Sendable {
    let device: Int64
    let inode: UInt64
    let generation: UInt32
    let changedAtSeconds: Int64
    let changedAtNanoseconds: Int64

    static func capture(at path: String) -> PluginInstallationIdentity? {
        var metadata = stat()
        guard Darwin.lstat(path, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              metadata.st_uid == geteuid()
        else {
            return nil
        }
        return PluginInstallationIdentity(
            device: Int64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            generation: metadata.st_gen,
            changedAtSeconds: Int64(metadata.st_ctimespec.tv_sec),
            changedAtNanoseconds: Int64(metadata.st_ctimespec.tv_nsec)
        )
    }
}

private struct PreparedPluginExecution: Sendable {
    let pluginID: String
    let scriptPath: String
    let pluginDirectory: String
    let environment: [String: String]
    let capabilities: Set<PluginCapability>
    let authorization: PluginExecutionAuthorization
}

private enum PluginRegistryLockAttempt<Value> {
    case acquired(Value)
}

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
    case registryBusy
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
/// Plugins are stored as directories in `~/.cocxy/plugins/` by default.
/// Existing `~/.config/cocxy/plugins/` installs are still discovered when the
/// new directory does not exist yet.
/// Each directory must contain `cocxy-plugin.toml` or the legacy
/// `manifest.toml` file. Enabled/disabled state is tracked locally.
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
    private let sandbox: any PluginSandboxing
    private let grantedCapabilitiesProvider: @Sendable (String) -> Set<PluginCapability>
    private var authorizationResetObserver: PluginAuthorizationResetObservation?

    // MARK: - Initialization

    init(
        fileSystem: any PluginFileSystem = DiskPluginFileSystem(),
        pluginsDirectory: String = PluginManager.defaultPluginsDirectory(),
        sandbox: any PluginSandboxing = PluginSandbox(),
        grantedCapabilitiesProvider: (@Sendable (String) -> Set<PluginCapability>)? = nil
    ) {
        let canonicalPluginsDirectory = PluginRegistrySynchronization
            .canonicalDirectoryURL(
                URL(fileURLWithPath: pluginsDirectory, isDirectory: true)
            )
        self.fileSystem = fileSystem
        self.pluginsDirectory = canonicalPluginsDirectory.path
        self.stateFilePath = canonicalPluginsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("plugins.json", isDirectory: false)
            .path
        self.sandbox = sandbox
        self.grantedCapabilitiesProvider = grantedCapabilitiesProvider
            ?? { pluginID in
                let store = PluginCapabilityGrantStore()
                let grants = (try? store.grants(for: pluginID)) ?? []
                return Set(grants.map(\.capability))
            }
        let observedPluginsDirectory = canonicalPluginsDirectory.path
        let observer = NotificationCenter.default.addObserver(
            forName: .cocxyPluginAuthorizationDidReset,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let pluginID = notification.userInfo?["pluginID"] as? String,
                  notification.userInfo?["pluginsDirectory"] as? String
                    == observedPluginsDirectory
            else {
                return
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.invalidateAuthorization(for: pluginID)
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.invalidateAuthorization(for: pluginID)
                }
            }
        }
        self.authorizationResetObserver = PluginAuthorizationResetObservation(token: observer)
    }

    nonisolated static func defaultPluginsDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> String {
        let current = homeDirectory.appendingPathComponent(".cocxy/plugins").path
        let legacy = homeDirectory.appendingPathComponent(".config/cocxy/plugins").path

        if directoryExists(at: current, fileManager: fileManager) {
            return current
        }
        if directoryExists(at: legacy, fileManager: fileManager) {
            return legacy
        }
        return current
    }

    private nonisolated static func directoryExists(at path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: - Discovery

    /// Scans the plugins directory and loads all valid plugin manifests.
    ///
    /// Merges discovered plugins with persisted enabled/disabled state.
    func scanPlugins() {
        _ = try? withRegistryReadLock {
            scanPluginsWithoutLocking()
        }
    }

    private func scanPluginsWithoutLocking() {
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
        let previousPlugins = plugins.reduce(into: [String: PluginState]()) { result, plugin in
            result[plugin.id] = plugin
        }

        plugins = subdirectories.compactMap { dirName -> PluginState? in
            let dirPath = "\(pluginsDirectory)/\(dirName)"
            let manifestCandidates = [
                PluginManifest.marketplaceManifestFileName,
                PluginManifest.legacyManifestFileName,
            ]
            guard let manifestFileName = manifestCandidates.first(where: {
                fileSystem.fileExists(at: "\(dirPath)/\($0)")
            }) else {
                return nil
            }
            let manifestPath = "\(dirPath)/\(manifestFileName)"

            guard fileSystem.fileExists(at: manifestPath),
                  let content = try? fileSystem.readFile(at: manifestPath),
                  let manifest = try? PluginManifestParser.parse(
                      content: content,
                      directoryPath: dirPath,
                      manifestFileName: manifestFileName
                  )
            else { return nil }

            return PluginState(
                manifest: manifest,
                isEnabled: enabledSet.contains(manifest.id),
                lastTriggeredAt: previousPlugins[manifest.id]?.manifest == manifest
                    ? previousPlugins[manifest.id]?.lastTriggeredAt
                    : nil
            )
        }
    }

    // MARK: - Enable / Disable

    /// Enables a plugin by its ID.
    func enablePlugin(id: String) throws {
        try withRegistryMutationLock {
            scanPluginsWithoutLocking()
            guard let index = plugins.firstIndex(where: { $0.id == id }) else {
                throw PluginManagerError.pluginNotFound(id)
            }
            guard !plugins[index].isEnabled else {
                throw PluginManagerError.alreadyEnabled(id)
            }

            plugins[index].isEnabled = true
            do {
                try saveEnabledState()
            } catch {
                plugins[index].isEnabled = false
                throw error
            }
        }
    }

    /// Disables a plugin by its ID.
    func disablePlugin(id: String) throws {
        try withRegistryMutationLock {
            scanPluginsWithoutLocking()
            guard let index = plugins.firstIndex(where: { $0.id == id }) else {
                throw PluginManagerError.pluginNotFound(id)
            }
            guard plugins[index].isEnabled else {
                throw PluginManagerError.alreadyDisabled(id)
            }

            plugins[index].isEnabled = false
            do {
                try saveEnabledState()
            } catch {
                plugins[index].isEnabled = true
                throw error
            }
        }
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
        let preparedExecutions: [PreparedPluginExecution] = (try? withRegistryReadLock {
            scanPluginsWithoutLocking()
            return plugins.compactMap { plugin -> PreparedPluginExecution? in
                guard plugin.isEnabled,
                      plugin.manifest.events.contains(event) else {
                    return nil
                }

                let scriptPath = "\(plugin.manifest.directoryPath)/\(event.scriptName)"
                guard fileSystem.fileExists(at: scriptPath) else { return nil }

                let installationIdentity: PluginInstallationIdentity?
                if fileSystem is DiskPluginFileSystem {
                    guard let captured = PluginInstallationIdentity.capture(
                        at: plugin.manifest.directoryPath
                    ) else {
                        return nil
                    }
                    installationIdentity = captured
                } else {
                    installationIdentity = nil
                }

                let capabilities = effectiveCapabilities(for: plugin.manifest)
                var authorizedEnvironment: [String: String] = [:]
                if capabilities.contains(.environmentRead) {
                    authorizedEnvironment = environment
                }
                authorizedEnvironment["COCXY_EVENT"] = event.rawValue

                return PreparedPluginExecution(
                    pluginID: plugin.id,
                    scriptPath: scriptPath,
                    pluginDirectory: plugin.manifest.directoryPath,
                    environment: authorizedEnvironment,
                    capabilities: capabilities,
                    authorization: makeExecutionAuthorization(
                        for: plugin,
                        expectedCapabilities: capabilities,
                        expectedInstallationIdentity: installationIdentity
                    )
                )
            }
        }) ?? []

        for execution in preparedExecutions {
            sandbox.execute(
                scriptPath: execution.scriptPath,
                environment: execution.environment,
                pluginID: execution.pluginID,
                pluginDirectory: execution.pluginDirectory,
                capabilities: execution.capabilities,
                authorization: execution.authorization
            )

            // Update last triggered timestamp.
            if let index = plugins.firstIndex(where: { $0.id == execution.pluginID }) {
                plugins[index].lastTriggeredAt = Date()
            }
        }
    }

    // MARK: - Queries

    /// Returns all enabled plugins.
    var enabledPlugins: [PluginState] {
        (try? withRegistryReadLock {
            scanPluginsWithoutLocking()
            return plugins.filter(\.isEnabled)
        }) ?? []
    }

    /// Returns a plugin by its ID.
    func plugin(id: String) -> PluginState? {
        try? withRegistryReadLock {
            scanPluginsWithoutLocking()
            return plugins.first { $0.id == id }
        }
    }

    // MARK: - State Persistence

    /// Loads the set of enabled plugin IDs from disk.
    private func loadEnabledState() -> Set<String> {
        Self.loadEnabledState(
            fileSystem: fileSystem,
            stateFilePath: stateFilePath
        )
    }

    private nonisolated static func loadEnabledState(
        fileSystem: any PluginFileSystem,
        stateFilePath: String
    ) -> Set<String> {
        guard let content = try? fileSystem.readFile(at: stateFilePath),
              let data = content.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }

    /// Saves the set of enabled plugin IDs to disk.
    private func saveEnabledState() throws {
        let enabledIDs = plugins.filter(\.isEnabled).map(\.id).sorted()
        let data = try JSONEncoder().encode(enabledIDs)
        let json = String(decoding: data, as: UTF8.self)
        try fileSystem.writeFile(at: stateFilePath, contents: json)
    }

    private func invalidateAuthorization(for pluginID: String) {
        guard let index = plugins.firstIndex(where: { $0.id == pluginID }) else { return }
        plugins[index].isEnabled = false
    }

    private func withRegistryMutationLock<T>(_ operation: () throws -> T) throws -> T {
        let directoryURL = URL(fileURLWithPath: pluginsDirectory, isDirectory: true)
        let attempt = try PluginRegistrySynchronization.shared.withProcessLockIfAvailable(
            pluginsDirectory: directoryURL
        ) {
            if fileSystem is DiskPluginFileSystem,
               fileSystem.directoryExists(at: pluginsDirectory) {
                guard let result = try PluginRegistrySynchronization.shared
                    .withFileLockIfAvailable(
                        pluginsDirectory: directoryURL,
                        operation
                    ) else {
                    throw PluginManagerError.registryBusy
                }
                return PluginRegistryLockAttempt.acquired(result)
            }
            return PluginRegistryLockAttempt.acquired(try operation())
        }
        guard case .acquired(let result)? = attempt else {
            throw PluginManagerError.registryBusy
        }
        return result
    }

    private func withRegistryReadLock<T>(_ operation: () throws -> T) throws -> T {
        let directoryURL = URL(fileURLWithPath: pluginsDirectory, isDirectory: true)
        return try PluginRegistrySynchronization.shared.withProcessReadLock(
            pluginsDirectory: directoryURL
        ) {
            guard fileSystem is DiskPluginFileSystem,
                  fileSystem.directoryExists(at: pluginsDirectory) else {
                return try operation()
            }
            return try PluginRegistrySynchronization.shared.withSharedFileLock(
                pluginsDirectory: directoryURL,
                operation
            )
        }
    }

    private func effectiveCapabilities(for manifest: PluginManifest) -> Set<PluginCapability> {
        let granted = grantedCapabilitiesProvider(manifest.id)
        return manifest.capabilities.intersection(granted)
    }

    private func makeExecutionAuthorization(
        for plugin: PluginState,
        expectedCapabilities: Set<PluginCapability>,
        expectedInstallationIdentity: PluginInstallationIdentity?
    ) -> PluginExecutionAuthorization {
        let fileSystem = self.fileSystem
        let stateFilePath = self.stateFilePath
        let pluginsDirectory = URL(
            fileURLWithPath: self.pluginsDirectory,
            isDirectory: true
        )
        let grantedCapabilitiesProvider = self.grantedCapabilitiesProvider
        let pluginID = plugin.id
        let pluginDirectory = plugin.manifest.directoryPath
        let manifestCapabilities = plugin.manifest.capabilities

        return PluginExecutionAuthorization(
            pluginsDirectory: pluginsDirectory
        ) {
            guard Self.loadEnabledState(
                fileSystem: fileSystem,
                stateFilePath: stateFilePath
            ).contains(pluginID) else {
                return false
            }
            if let expectedInstallationIdentity,
               PluginInstallationIdentity.capture(at: pluginDirectory)
                != expectedInstallationIdentity {
                return false
            }
            let currentCapabilities = manifestCapabilities.intersection(
                grantedCapabilitiesProvider(pluginID)
            )
            return expectedCapabilities.isSubset(of: currentCapabilities)
        }
    }
}
