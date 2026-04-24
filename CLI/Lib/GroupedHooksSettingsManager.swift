// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GroupedHooksSettingsManager.swift - Shared JSON hook file manager for Codex and Gemini.

import Foundation

struct GroupedHooksSettingsManager {
    let settingsFilePath: String
    let hookEvents: [String]
    let hookCommand: String

    init(
        settingsFilePath: String,
        hookEvents: [String],
        hookCommand: String = ClaudeSettingsManager.cocxyHookCommand
    ) {
        self.settingsFilePath = settingsFilePath
        self.hookEvents = hookEvents
        self.hookCommand = hookCommand
    }

    func installHooks() throws -> HooksInstallResult {
        var settings = try readOrCreateSettings()
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]

        var modified = false

        for eventType in hookEvents {
            var eventHooks = (hooks[eventType] as? [[String: Any]]) ?? []
            let desiredEntry: [String: Any] = [
                "matcher": "",
                "hooks": [
                    ["type": "command", "command": hookCommand]
                ]
            ]

            let reconciliation = ClaudeSettingsManager.reconciledHookEntries(
                eventHooks,
                desiredEntry: desiredEntry,
                expectedCommand: hookCommand
            )
            eventHooks = reconciliation.entries
            modified = modified || reconciliation.modified
            hooks[eventType] = eventHooks
        }

        guard modified else {
            return HooksInstallResult(
                installed: false,
                alreadyInstalled: true,
                hookEvents: hookEvents
            )
        }

        try createBackupIfNeeded()
        settings["hooks"] = hooks
        try writeSettings(settings)

        return HooksInstallResult(
            installed: true,
            alreadyInstalled: false,
            hookEvents: hookEvents
        )
    }

    func uninstallHooks() throws -> HooksUninstallResult {
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

        for eventType in hookEvents {
            guard var eventHooks = hooks[eventType] as? [[String: Any]] else {
                continue
            }

            let originalCount = eventHooks.count
            eventHooks.removeAll { ClaudeSettingsManager.hookEntryContainsCocxyCommand($0) }

            if eventHooks.count < originalCount {
                removedEvents.append(eventType)
            }

            if eventHooks.isEmpty {
                hooks.removeValue(forKey: eventType)
            } else {
                hooks[eventType] = eventHooks
            }
        }

        guard !removedEvents.isEmpty else {
            return HooksUninstallResult(
                uninstalled: false,
                nothingToRemove: true,
                removedEvents: []
            )
        }

        try createBackupIfNeeded()
        settings["hooks"] = hooks
        try writeSettings(settings)

        return HooksUninstallResult(
            uninstalled: true,
            nothingToRemove: false,
            removedEvents: removedEvents
        )
    }

    func hooksStatus() throws -> HooksStatusResult {
        guard FileManager.default.fileExists(atPath: settingsFilePath) else {
            return HooksStatusResult(installed: false, installedEvents: [])
        }

        let settings = try readSettings()
        guard let hooks = settings["hooks"] as? [String: Any] else {
            return HooksStatusResult(installed: false, installedEvents: [])
        }

        let installedEvents = hookEvents.filter { eventType in
            guard let eventHooks = hooks[eventType] as? [[String: Any]] else {
                return false
            }
            return eventHooks.contains(where: ClaudeSettingsManager.hookEntryContainsCocxyCommand)
        }

        return HooksStatusResult(
            installed: !installedEvents.isEmpty,
            installedEvents: installedEvents
        )
    }

    private func readOrCreateSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsFilePath) else {
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
            let object = try JSONSerialization.jsonObject(with: data)
            guard let settings = object as? [String: Any] else {
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
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw HooksError.fileSystemError(
                reason: "Could not create directory \(directoryURL.path): \(error.localizedDescription)"
            )
        }

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw HooksError.fileSystemError(
                reason: "Could not encode settings JSON: \(error.localizedDescription)"
            )
        }

        do {
            try data.write(to: URL(fileURLWithPath: settingsFilePath), options: .atomic)
        } catch {
            throw HooksError.fileSystemError(
                reason: "Could not write \(settingsFilePath): \(error.localizedDescription)"
            )
        }
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
            throw HooksError.fileSystemError(
                reason: "Could not create backup \(backupPath): \(error.localizedDescription)"
            )
        }
    }

}
