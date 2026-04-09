// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ConfigWatcher.swift - Hot-reload of config files via file system observation.

import Foundation

// MARK: - Config Watcher

/// Watches `config.toml` for changes and triggers a reload on `ConfigService`.
///
/// Uses `DispatchSource.makeFileSystemObjectSource` in production to detect
/// file modifications. Includes a debounce mechanism (default 500ms) to avoid
/// reloading multiple times when an editor writes the file in stages.
///
/// If the reloaded config is invalid (malformed TOML), `ConfigService` falls
/// back to defaults. The watcher never crashes.
///
/// - SeeAlso: ADR-005 (TOML config format)
final class ConfigWatcher {

    // MARK: - Properties

    /// The config service that will be reloaded when the file changes.
    private let configService: ConfigService

    /// The file provider used to read config content (for reload).
    private let fileProvider: ConfigFileProviding

    /// Absolute path to the config file being watched.
    private let configPath: String

    /// Whether the watcher is currently active.
    private(set) var isWatching: Bool = false

    /// Debounce interval in seconds. Rapid file changes within this
    /// window are coalesced into a single reload.
    var debounceInterval: TimeInterval = 0.5

    /// The dispatch source monitoring the config file.
    private var fileSource: DispatchSourceFileSystemObject?

    /// Dispatch source for parent directory (when target file doesn't exist yet).
    private var directorySource: DispatchSourceFileSystemObject?

    /// Work item for debounced reload.
    private var debounceWorkItem: DispatchWorkItem?

    // MARK: - Initialization

    /// Creates a watcher for the given config service.
    ///
    /// - Parameters:
    ///   - configService: The service to reload on file changes.
    ///   - fileProvider: The file provider for reading config content.
    init(configService: ConfigService, fileProvider: ConfigFileProviding) {
        self.configService = configService
        self.fileProvider = fileProvider
        self.configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/config.toml").path
    }

    deinit {
        stopWatching()
    }

    // MARK: - Watch Control

    /// Starts watching the config file for changes.
    ///
    /// Opens a file descriptor to `~/.config/cocxy/config.toml` and creates
    /// a `DispatchSourceFileSystemObject` to detect writes. When a write is
    /// detected, a debounced reload is scheduled.
    ///
    /// If already watching, this call is a no-op.
    /// If the config file does not exist yet, watching is deferred until it does.
    func startWatching() {
        guard !isWatching else { return }

        if FileManager.default.fileExists(atPath: configPath) {
            guard startFileWatching() else { return }
        } else {
            guard startDirectoryWatching() else { return }
        }
        isWatching = true
    }

    /// Stops watching the config file and cleans up resources.
    func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        fileSource?.cancel()
        fileSource = nil
        directorySource?.cancel()
        directorySource = nil
        isWatching = false
    }

    // MARK: - Private Watching Helpers

    /// Starts watching the config file directly via file descriptor.
    @discardableResult
    private func startFileWatching() -> Bool {
        directorySource?.cancel()
        directorySource = nil

        let fd = open(configPath, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else {
            NSLog("[ConfigWatcher] Failed to open config file for watching: %@", configPath)
            return false
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if events.contains(.rename) || events.contains(.delete) {
                // Atomic write (vim/emacs): file inode changed. Restart to track new inode.
                self.scheduleRestartFileWatching()
            } else {
                self.scheduleReload()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.fileSource = source
        return true
    }

    /// Watches the parent directory for file creation when the target doesn't exist yet.
    @discardableResult
    private func startDirectoryWatching() -> Bool {
        let parentDir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: parentDir, withIntermediateDirectories: true, attributes: nil
        )

        let dirFd = open(parentDir, O_EVTONLY | O_CLOEXEC)
        guard dirFd >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFd,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.configPath) {
                self.startFileWatching()
                self.scheduleReload()
            }
        }

        source.setCancelHandler {
            close(dirFd)
        }

        source.resume()
        self.directorySource = source
        return true
    }

    /// Debounced restart of file watching after rename/delete (atomic write recovery).
    private func scheduleRestartFileWatching() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.fileSource?.cancel()
            self.fileSource = nil
            if FileManager.default.fileExists(atPath: self.configPath) {
                self.startFileWatching()
                self.handleFileChange()
            } else {
                self.startDirectoryWatching()
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval, execute: workItem
        )
    }

    // MARK: - File Change Handling

    /// Directly handles a file change event. Called by the dispatch source
    /// or by tests to simulate a file change.
    ///
    /// Uses `reloadIfValid()` to preserve current config when the file
    /// is temporarily invalid (e.g., mid-edit in vim/emacs).
    func handleFileChange() {
        configService.reloadIfValid()
    }

    /// Schedules a debounced reload. Multiple calls within `debounceInterval`
    /// are coalesced into a single reload.
    func scheduleReload() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.handleFileChange()
        }

        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: workItem
        )
    }
}

// MARK: - Agent Config Watcher

/// Watches `agents.toml` for changes and triggers a reload of agent
/// detection patterns.
///
/// Uses `DispatchSource.makeFileSystemObjectSource` to detect file
/// modifications. Includes the same debounce mechanism as `ConfigWatcher`
/// (default 500ms) to coalesce rapid writes.
///
/// On each valid file change, calls `AgentConfigService.reload()` which
/// re-parses the TOML, re-compiles regex patterns, and emits via
/// `configChangedPublisher`. Downstream subscribers (the detection engine)
/// pick up the new patterns automatically.
///
/// - SeeAlso: `ConfigWatcher` for the analogous `config.toml` watcher.
/// - SeeAlso: ADR-004 (Agent detection strategy)
final class AgentConfigWatcher {

    // MARK: - Properties

    /// The agent config service to reload on file changes.
    private let agentConfigService: AgentConfigService

    /// The file provider for agent config (used to resolve the file path).
    private let fileProvider: AgentConfigFileProviding

    /// Absolute path to the agent config file being watched.
    private let configPath: String

    /// Whether the watcher is currently active.
    private(set) var isWatching: Bool = false

    /// Whether the last reload succeeded.
    private(set) var lastReloadSucceeded: Bool = false

    /// Debounce interval in seconds. Rapid file changes within this
    /// window are coalesced into a single reload.
    var debounceInterval: TimeInterval = 0.5

    /// The dispatch source monitoring the agent config file.
    private var fileSource: DispatchSourceFileSystemObject?

    /// Dispatch source for parent directory (when target file doesn't exist yet).
    private var directorySource: DispatchSourceFileSystemObject?

    /// Work item for debounced reload.
    private var debounceWorkItem: DispatchWorkItem?

    // MARK: - Initialization

    /// Creates a watcher for the given agent config service.
    ///
    /// - Parameters:
    ///   - agentConfigService: The service to reload on file changes.
    ///   - fileProvider: The file provider for reading agent config content.
    init(agentConfigService: AgentConfigService, fileProvider: AgentConfigFileProviding) {
        self.agentConfigService = agentConfigService
        self.fileProvider = fileProvider
        self.configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/agents.toml").path
    }

    deinit {
        stopWatching()
    }

    // MARK: - Watch Control

    /// Starts watching the agent config file for changes.
    ///
    /// Opens a file descriptor to `~/.config/cocxy/agents.toml` and creates
    /// a `DispatchSourceFileSystemObject` to detect writes. When a write is
    /// detected, a debounced reload is scheduled.
    ///
    /// If already watching, this call is a no-op.
    /// If the config file does not exist yet, watching is deferred.
    func startWatching() {
        guard !isWatching else { return }

        if FileManager.default.fileExists(atPath: configPath) {
            guard startFileWatching() else { return }
        } else {
            guard startDirectoryWatching() else { return }
        }
        isWatching = true
    }

    /// Stops watching the agent config file and cleans up resources.
    func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        fileSource?.cancel()
        fileSource = nil
        directorySource?.cancel()
        directorySource = nil
        isWatching = false
    }

    // MARK: - Private Watching Helpers

    @discardableResult
    private func startFileWatching() -> Bool {
        directorySource?.cancel()
        directorySource = nil

        let fd = open(configPath, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if events.contains(.rename) || events.contains(.delete) {
                self.scheduleRestartFileWatching()
            } else {
                self.scheduleReload()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.fileSource = source
        return true
    }

    @discardableResult
    private func startDirectoryWatching() -> Bool {
        let parentDir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: parentDir, withIntermediateDirectories: true, attributes: nil
        )

        let dirFd = open(parentDir, O_EVTONLY | O_CLOEXEC)
        guard dirFd >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFd,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.configPath) {
                self.startFileWatching()
                self.handleFileChange()
            }
        }

        source.setCancelHandler {
            close(dirFd)
        }

        source.resume()
        self.directorySource = source
        return true
    }

    private func scheduleRestartFileWatching() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.fileSource?.cancel()
            self.fileSource = nil
            if FileManager.default.fileExists(atPath: self.configPath) {
                self.startFileWatching()
                self.handleFileChange()
            } else {
                self.startDirectoryWatching()
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval, execute: workItem
        )
    }

    // MARK: - File Change Handling

    /// Directly handles a file change event. Called by the dispatch source
    /// or by tests to simulate a file change.
    ///
    /// Delegates to `agentConfigService.reload()` which handles validation
    /// internally. If the file is invalid, the service preserves its current
    /// state rather than falling back to defaults.
    func handleFileChange() {
        do {
            try agentConfigService.reloadIfValid()
            lastReloadSucceeded = true
        } catch {
            lastReloadSucceeded = false
        }
    }

    /// Schedules a debounced reload. Multiple calls within `debounceInterval`
    /// are coalesced into a single reload.
    func scheduleReload() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.handleFileChange()
        }

        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: workItem
        )
    }
}
