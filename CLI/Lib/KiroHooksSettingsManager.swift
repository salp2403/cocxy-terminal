// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KiroHooksSettingsManager.swift - Kiro CLI hook settings installer.

import Foundation

struct KiroHooksSettingsManager {
    static let hookEvents = ["agentSpawn", "userPromptSubmit", "preToolUse", "postToolUse", "stop"]
    static let matcherEvents: Set<String> = ["preToolUse", "postToolUse"]

    let settingsFilePath: String
    let hookCommand: String
    let fileManager: FileManager

    init(
        settingsFilePath: String,
        hookCommand: String = ClaudeSettingsManager.hookCommand(for: .kiro),
        fileManager: FileManager = .default
    ) {
        self.settingsFilePath = settingsFilePath
        self.hookCommand = hookCommand
        self.fileManager = fileManager
    }

    func installHooks() throws -> HooksInstallResult {
        var settings = try readOrCreateSettings()
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        var modified = false

        for event in Self.hookEvents {
            var entries = (hooks[event] as? [[String: Any]]) ?? []
            let reconciliation = Self.reconciledEntries(
                entries,
                desiredEntry: desiredEntry(for: event),
                expectedCommand: hookCommand
            )
            entries = reconciliation.entries
            modified = modified || reconciliation.modified
            hooks[event] = entries
        }

        guard modified else {
            return HooksInstallResult(installed: false, alreadyInstalled: true, hookEvents: Self.hookEvents)
        }

        try createBackupIfNeeded()
        settings["hooks"] = hooks
        try writeSettings(settings)
        return HooksInstallResult(installed: true, alreadyInstalled: false, hookEvents: Self.hookEvents)
    }

    func uninstallHooks() throws -> HooksUninstallResult {
        guard fileManager.fileExists(atPath: settingsFilePath) else {
            return HooksUninstallResult(uninstalled: false, nothingToRemove: true, removedEvents: [])
        }

        var settings = try readSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else {
            return HooksUninstallResult(uninstalled: false, nothingToRemove: true, removedEvents: [])
        }

        var removedEvents: [String] = []
        for event in Self.hookEvents {
            guard var entries = hooks[event] as? [[String: Any]] else {
                continue
            }

            let originalCount = entries.count
            entries.removeAll(where: Self.entryContainsCocxyCommand)
            if entries.count < originalCount {
                removedEvents.append(event)
            }

            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        guard !removedEvents.isEmpty else {
            return HooksUninstallResult(uninstalled: false, nothingToRemove: true, removedEvents: [])
        }

        try createBackupIfNeeded()
        settings["hooks"] = hooks
        try writeSettings(settings)
        return HooksUninstallResult(uninstalled: true, nothingToRemove: false, removedEvents: removedEvents)
    }

    func hooksStatus() throws -> HooksStatusResult {
        guard fileManager.fileExists(atPath: settingsFilePath) else {
            return HooksStatusResult(installed: false, installedEvents: [])
        }

        let settings = try readSettings()
        guard let hooks = settings["hooks"] as? [String: Any] else {
            return HooksStatusResult(installed: false, installedEvents: [])
        }

        let installedEvents = Self.hookEvents.filter { event in
            guard let entries = hooks[event] as? [[String: Any]] else {
                return false
            }
            return entries.contains(where: Self.entryContainsCocxyCommand)
        }
        return HooksStatusResult(installed: !installedEvents.isEmpty, installedEvents: installedEvents)
    }

    private func desiredEntry(for event: String) -> [String: Any] {
        if Self.matcherEvents.contains(event) {
            return ["matcher": "*", "command": hookCommand]
        }
        return ["command": hookCommand]
    }

    private func readOrCreateSettings() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: settingsFilePath) else {
            return [:]
        }
        return try readSettings()
    }

    private func readSettings() throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: settingsFilePath))
        } catch {
            throw HooksError.fileSystemError(
                reason: "Could not read \(settingsFilePath): \(error.localizedDescription)"
            )
        }

        do {
            guard let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HooksError.malformedSettingsFile(path: settingsFilePath)
            }
            return settings
        } catch {
            if let hooksError = error as? HooksError {
                throw hooksError
            }
            throw HooksError.malformedSettingsFile(path: settingsFilePath)
        }
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let directoryURL = URL(fileURLWithPath: settingsFilePath).deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: settingsFilePath), options: .atomic)
    }

    private func createBackupIfNeeded() throws {
        guard fileManager.fileExists(atPath: settingsFilePath) else {
            return
        }

        let backupPath = "\(settingsFilePath).cocxy-backup"
        guard !fileManager.fileExists(atPath: backupPath) else {
            return
        }
        try fileManager.copyItem(
            at: URL(fileURLWithPath: settingsFilePath),
            to: URL(fileURLWithPath: backupPath)
        )
    }

    static func reconciledEntries(
        _ entries: [[String: Any]],
        desiredEntry: [String: Any],
        expectedCommand: String
    ) -> (entries: [[String: Any]], modified: Bool) {
        let cocxyIndices = entries.indices.filter { entryContainsCocxyCommand(entries[$0]) }
        guard !cocxyIndices.isEmpty else {
            return (entries + [desiredEntry], true)
        }

        if let keeperIndex = cocxyIndices.first(where: {
            entryContainsAcceptableCocxyCommand(entries[$0], expectedCommand: expectedCommand)
        }) {
            guard cocxyIndices.count > 1 else {
                return (entries, false)
            }

            var deduplicated = entries
            for index in cocxyIndices.reversed() where index != keeperIndex {
                deduplicated.remove(at: index)
            }
            return (deduplicated, true)
        }

        var rewritten = entries
        for index in cocxyIndices.reversed() {
            rewritten.remove(at: index)
        }
        rewritten.append(desiredEntry)
        return (rewritten, true)
    }

    static func entryContainsCocxyCommand(_ entry: [String: Any]) -> Bool {
        guard let command = entry["command"] as? String else {
            return false
        }
        return command.contains("cocxy") && command.contains("hook-handler")
    }

    static func entryContainsAcceptableCocxyCommand(_ entry: [String: Any], expectedCommand: String) -> Bool {
        guard let command = entry["command"] as? String else {
            return false
        }
        return ClaudeSettingsManager.isAcceptableInstalledHookCommand(command, expectedCommand: expectedCommand)
    }
}
