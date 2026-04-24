// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ClaudeSettingsManager.swift - Reads/writes Claude Code settings.json for hooks management.

import Foundation

// MARK: - Claude Settings Manager

/// Manages hooks entries in `~/.claude/settings.json`.
///
/// Provides install, uninstall, and status operations that:
/// - Merge cocxy hooks without overwriting existing user hooks.
/// - Preserve all non-hook settings in the file.
/// - Are idempotent (re-installing is a no-op).
///
/// Each hook entry follows Claude Code's format:
/// ```json
/// {
///   "matcher": "",
///   "hooks": [{ "type": "command", "command": "cocxy hook-handler" }]
/// }
/// ```
public struct ClaudeSettingsManager {

    // MARK: - Constants

    /// The command that cocxy registers as a hook handler.
    ///
    /// When running from inside an app bundle (symlink points to `.app/Contents/Resources/`),
    /// uses the absolute path so hooks work without `cocxy` in PATH.
    /// Otherwise falls back to bare `cocxy hook-handler`.
    static let cocxyHookCommand: String = {
        let executablePath = ProcessInfo.processInfo.arguments[0]
        let resolved = (try? FileManager.default.destinationOfSymbolicLink(atPath: executablePath))
            ?? executablePath
        return hookCommand(forExecutablePath: resolved)
    }()

    static let installedAppCLIPath = "/Applications/Cocxy Terminal.app/Contents/Resources/cocxy"
    private static let ephemeralPathPrefixes = ["/private/tmp/", "/tmp/"]
    private static let ephemeralPathSubstrings = ["/TemporaryItems/", "/AppTranslocation/", "/build/"]

    static func hookCommand(
        forExecutablePath executablePath: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        let absolutePath = URL(fileURLWithPath: executablePath).standardized.path

        guard absolutePath.contains(".app/Contents/Resources/") else {
            return "cocxy hook-handler"
        }

        let persistentPath: String?
        if isEphemeralOrDevelopmentCLIPath(absolutePath) {
            persistentPath = fileExists(installedAppCLIPath) ? installedAppCLIPath : nil
        } else {
            persistentPath = absolutePath
        }

        guard let persistentPath else {
            return "cocxy hook-handler"
        }
        return "\(shellSingleQuoted(persistentPath)) hook-handler"
    }

    static func isEphemeralOrDevelopmentCLIPath(_ path: String) -> Bool {
        ephemeralPathPrefixes.contains { path.hasPrefix($0) }
            || containsEphemeralOrDevelopmentPath(in: path)
    }

    static func containsEphemeralOrDevelopmentPath(in value: String) -> Bool {
        ephemeralPathSubstrings.contains { value.contains($0) }
            || ephemeralPathPrefixes.contains { value.contains($0) }
    }

    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func hookCommand(for source: AgentSource?) -> String {
        guard let source, source != .claudeCode else {
            return cocxyHookCommand
        }
        return "COCXY_HOOK_AGENT=\(source.cliArgumentName) \(cocxyHookCommand)"
    }

    static func isAcceptableInstalledHookCommand(_ commandString: String, expectedCommand: String) -> Bool {
        if commandString == expectedCommand {
            return true
        }

        guard commandString.contains("cocxy"),
              commandString.contains("hook-handler") else {
            return false
        }

        let expectedAgentMarker = expectedCommand
            .split(separator: " ")
            .first { $0.hasPrefix("COCXY_HOOK_AGENT=") }
        if let expectedAgentMarker,
           !commandString.contains(expectedAgentMarker) {
            return false
        }

        guard commandString.contains(".app/Contents/Resources/cocxy") else {
            return true
        }
        return !containsEphemeralOrDevelopmentPath(in: commandString)
    }

    /// The hook event types that cocxy registers for.
    ///
    /// Includes all Claude Code hook events that drive agent detection:
    /// - SessionStart/SessionEnd: agent lifecycle tracking.
    /// - Stop/TaskCompleted: completion detection.
    /// - PreToolUse/PostToolUse: working state indicators.
    /// - SubagentStop: sub-agent lifecycle.
    /// - Notification: OSC notification forwarding.
    /// - TeammateIdle: waiting-for-input detection (drives notification ring).
    /// - UserPromptSubmit: user interaction tracking.
    /// - CwdChanged: keep tab.workingDirectory in sync with agent `cd` (2.1.83+).
    /// - FileChanged: drive code-review auto-refresh and dashboard file
    ///   attribution (2.1.83+).
    ///
    /// Important: this array is mirrored by
    /// `AppDelegate+FirstLaunchSetup.eventTypes` because the GUI app cannot
    /// import `CocxyCLILib` directly. When extending this list, update the
    /// AppDelegate copy too — the count assertion in HooksCommandTests uses
    /// `Self.hookedEventTypes.count`, which will surface a drift on the
    /// CLI side; visual inspection covers the AppDelegate side.
    static let hookedEventTypes: [String] = [
        "SessionStart",
        "SessionEnd",
        "Stop",
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        "SubagentStart",
        "SubagentStop",
        "Notification",
        "TeammateIdle",
        "TaskCompleted",
        "UserPromptSubmit",
        "CwdChanged",
        "FileChanged"
    ]

    /// Default path to Claude Code's settings file.
    public static let defaultSettingsFilePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/settings.json"
    }()

    // MARK: - Properties

    /// Path to the settings file.
    let settingsFilePath: String

    // MARK: - Initialization

    /// Creates a settings manager.
    ///
    /// - Parameter settingsFilePath: Path to `settings.json`.
    ///   Defaults to `~/.claude/settings.json`.
    public init(settingsFilePath: String = ClaudeSettingsManager.defaultSettingsFilePath) {
        self.settingsFilePath = settingsFilePath
    }

    // MARK: - Install

    /// Installs cocxy hooks into the Claude Code settings file.
    ///
    /// If the file does not exist, creates it with the hooks.
    /// If hooks are already installed with an acceptable persistent command,
    /// returns without modifying the file. Stale temporary/build-bundle paths
    /// are rewritten to the current safe command.
    /// Preserves all existing user hooks and non-hook settings.
    ///
    /// - Returns: The install result indicating what happened.
    /// - Throws: `HooksError` on file or parsing errors.
    public func installHooks() throws -> HooksInstallResult {
        var settings = try readOrCreateSettings()

        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]

        var modified = false

        for eventType in Self.hookedEventTypes {
            var eventHooks = (hooks[eventType] as? [[String: Any]]) ?? []
            let desiredEntry: [String: Any] = [
                "matcher": "",
                "hooks": [
                    ["type": "command", "command": Self.cocxyHookCommand]
                ]
            ]

            let reconciliation = Self.reconciledHookEntries(
                eventHooks,
                desiredEntry: desiredEntry,
                expectedCommand: Self.cocxyHookCommand
            )
            eventHooks = reconciliation.entries
            modified = modified || reconciliation.modified
            hooks[eventType] = eventHooks
        }

        guard modified else {
            return HooksInstallResult(
                installed: false,
                alreadyInstalled: true,
                hookEvents: Self.hookedEventTypes
            )
        }

        settings["hooks"] = hooks

        try createBackupIfNeeded()
        try writeSettings(settings)

        return HooksInstallResult(
            installed: true,
            alreadyInstalled: false,
            hookEvents: Self.hookedEventTypes
        )
    }

    // MARK: - Uninstall

    /// Removes cocxy hooks from the Claude Code settings file.
    ///
    /// Only removes entries that contain "cocxy hook-handler".
    /// Preserves all user hooks and non-hook settings.
    /// Empty event arrays are cleaned up after removal.
    ///
    /// - Returns: The uninstall result indicating what happened.
    /// - Throws: `HooksError` on file or parsing errors.
    public func uninstallHooks() throws -> HooksUninstallResult {
        guard FileManager.default.fileExists(atPath: settingsFilePath) else {
            return HooksUninstallResult(
                uninstalled: false,
                nothingToRemove: true,
                removedEvents: []
            )
        }

        var settings = try readSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else {
            return HooksUninstallResult(
                uninstalled: false,
                nothingToRemove: true,
                removedEvents: []
            )
        }

        var removedEvents: [String] = []

        for eventType in Self.hookedEventTypes {
            guard var eventHooks = hooks[eventType] as? [[String: Any]] else {
                continue
            }

            let originalCount = eventHooks.count
            eventHooks.removeAll { entry in
                Self.hookEntryContainsCocxyCommand(entry)
            }

            if eventHooks.count < originalCount {
                removedEvents.append(eventType)
            }

            if eventHooks.isEmpty {
                hooks.removeValue(forKey: eventType)
            } else {
                hooks[eventType] = eventHooks
            }
        }

        settings["hooks"] = hooks

        if removedEvents.isEmpty {
            return HooksUninstallResult(
                uninstalled: false,
                nothingToRemove: true,
                removedEvents: []
            )
        }

        try createBackupIfNeeded()
        try writeSettings(settings)

        return HooksUninstallResult(
            uninstalled: true,
            nothingToRemove: false,
            removedEvents: removedEvents
        )
    }

    // MARK: - Status

    /// Checks the status of cocxy hooks in the Claude Code settings file.
    ///
    /// - Returns: The status result showing which events have hooks installed.
    /// - Throws: `HooksError` on file or parsing errors.
    public func hooksStatus() throws -> HooksStatusResult {
        guard FileManager.default.fileExists(atPath: settingsFilePath) else {
            return HooksStatusResult(installed: false, installedEvents: [])
        }

        let settings = try readSettings()
        guard let hooks = settings["hooks"] as? [String: Any] else {
            return HooksStatusResult(installed: false, installedEvents: [])
        }

        var installedEvents: [String] = []
        for eventType in Self.hookedEventTypes {
            guard let eventHooks = hooks[eventType] as? [[String: Any]] else {
                continue
            }
            if eventHooks.contains(where: { Self.hookEntryContainsCocxyCommand($0) }) {
                installedEvents.append(eventType)
            }
        }

        return HooksStatusResult(
            installed: !installedEvents.isEmpty,
            installedEvents: installedEvents
        )
    }

    // MARK: - Private: File I/O

    /// Reads the settings file, or returns an empty dictionary if it does not exist.
    private func readOrCreateSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsFilePath) else {
            return [:]
        }
        return try readSettings()
    }

    /// Reads and parses the settings file.
    private func readSettings() throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: settingsFilePath))
        } catch {
            throw HooksError.fileSystemError(reason: error.localizedDescription)
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HooksError.malformedSettingsFile(path: settingsFilePath)
        }

        guard let settings = jsonObject as? [String: Any] else {
            throw HooksError.malformedSettingsFile(path: settingsFilePath)
        }

        return settings
    }

    /// Writes settings back to the file.
    private func writeSettings(_ settings: [String: Any]) throws {
        // Ensure directory exists
        let directory = (settingsFilePath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: directory) {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
        }

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: settingsFilePath), options: .atomic)
    }

    private func createBackupIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: settingsFilePath) else {
            return
        }

        let backupPath = "\(settingsFilePath).cocxy-backup"
        guard !FileManager.default.fileExists(atPath: backupPath) else {
            return
        }

        do {
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: settingsFilePath),
                to: URL(fileURLWithPath: backupPath)
            )
        } catch {
            throw HooksError.fileSystemError(reason: error.localizedDescription)
        }
    }

    // MARK: - Private: Hook Detection

    /// Checks if a hook entry contains the cocxy hook-handler command.
    ///
    /// Uses separate substring checks for "cocxy" and "hook-handler" to handle
    /// both quoted (`'/path/cocxy' hook-handler`) and unquoted (`/path/cocxy hook-handler`)
    /// command formats. The quoted format is needed because the app bundle path
    /// contains spaces ("Cocxy Terminal.app").
    static func reconciledHookEntries(
        _ eventHooks: [[String: Any]],
        desiredEntry: [String: Any],
        expectedCommand: String
    ) -> (entries: [[String: Any]], modified: Bool) {
        let cocxyIndices = eventHooks.indices.filter {
            hookEntryContainsCocxyCommand(eventHooks[$0])
        }

        guard !cocxyIndices.isEmpty else {
            return (eventHooks + [desiredEntry], true)
        }

        if let keeperIndex = cocxyIndices.first(where: {
            hookEntryContainsAcceptableCocxyCommand(
                eventHooks[$0],
                expectedCommand: expectedCommand
            )
        }) {
            guard cocxyIndices.count > 1 else {
                return (eventHooks, false)
            }

            var deduplicated = eventHooks
            for idx in cocxyIndices.reversed() where idx != keeperIndex {
                deduplicated.remove(at: idx)
            }
            return (deduplicated, true)
        }

        var rewritten = eventHooks
        for idx in cocxyIndices.reversed() {
            rewritten.remove(at: idx)
        }
        rewritten.append(desiredEntry)
        return (rewritten, true)
    }

    static func hookEntryContainsCocxyCommand(_ hookEntry: [String: Any]) -> Bool {
        guard let hookCommands = hookEntry["hooks"] as? [[String: Any]] else {
            return false
        }
        return hookCommands.contains { command in
            guard let commandString = command["command"] as? String else {
                return false
            }
            return commandString.contains("cocxy") && commandString.contains("hook-handler")
        }
    }

    static func hookEntryContainsAcceptableCocxyCommand(
        _ hookEntry: [String: Any],
        expectedCommand: String
    ) -> Bool {
        guard let hookCommands = hookEntry["hooks"] as? [[String: Any]] else {
            return false
        }
        return hookCommands.contains { command in
            guard let commandString = command["command"] as? String else {
                return false
            }
            return Self.isAcceptableInstalledHookCommand(
                commandString,
                expectedCommand: expectedCommand
            )
        }
    }
}
