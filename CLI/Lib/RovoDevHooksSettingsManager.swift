// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RovoDevHooksSettingsManager.swift - Rovo Dev eventHooks config installer.

import Foundation

struct RovoDevHooksSettingsManager {
    static let beginMarker = "# Cocxy managed Rovo Dev hooks begin"
    static let endMarker = "# Cocxy managed Rovo Dev hooks end"
    static let eventMappings: [(rovoEvent: String, cocxyEvent: String)] = [
        ("on_complete", "TaskCompleted"),
        ("on_error", "Stop"),
        ("on_tool_permission", "PreToolUse")
    ]

    let configFilePath: String
    let fileManager: FileManager

    init(
        configFilePath: String,
        fileManager: FileManager = .default
    ) {
        self.configFilePath = configFilePath
        self.fileManager = fileManager
    }

    func installHooks() throws -> HooksInstallResult {
        let desired = Self.fullConfigTemplate()
        if !fileManager.fileExists(atPath: configFilePath) {
            try writeConfig(desired)
            return HooksInstallResult(installed: true, alreadyInstalled: false, hookEvents: Self.hookEvents)
        }

        let existing = try readConfig()
        if Self.installedEvents(in: existing) == Self.hookEvents {
            return HooksInstallResult(installed: false, alreadyInstalled: true, hookEvents: Self.hookEvents)
        }

        let reconciled = Self.reconciledConfig(existing)
        guard reconciled != existing else {
            return HooksInstallResult(installed: false, alreadyInstalled: true, hookEvents: Self.hookEvents)
        }

        try createBackupIfNeeded()
        try writeConfig(reconciled)
        return HooksInstallResult(installed: true, alreadyInstalled: false, hookEvents: Self.hookEvents)
    }

    func uninstallHooks() throws -> HooksUninstallResult {
        guard fileManager.fileExists(atPath: configFilePath) else {
            return HooksUninstallResult(uninstalled: false, nothingToRemove: true, removedEvents: [])
        }

        let existing = try readConfig()
        guard existing.contains(Self.beginMarker) else {
            return HooksUninstallResult(uninstalled: false, nothingToRemove: true, removedEvents: [])
        }

        if existing.trimmingCharacters(in: .whitespacesAndNewlines)
            == Self.fullConfigTemplate().trimmingCharacters(in: .whitespacesAndNewlines) {
            try fileManager.removeItem(at: URL(fileURLWithPath: configFilePath))
            return HooksUninstallResult(uninstalled: true, nothingToRemove: false, removedEvents: Self.hookEvents)
        }

        let stripped = Self.removingManagedBlock(from: existing)
        try createBackupIfNeeded()
        try writeConfig(stripped)
        return HooksUninstallResult(uninstalled: true, nothingToRemove: false, removedEvents: Self.hookEvents)
    }

    func hooksStatus() throws -> HooksStatusResult {
        guard fileManager.fileExists(atPath: configFilePath) else {
            return HooksStatusResult(installed: false, installedEvents: [])
        }
        let existing = try readConfig()
        let installed = Self.installedEvents(in: existing)
        return HooksStatusResult(installed: !installed.isEmpty, installedEvents: installed)
    }

    private func readConfig() throws -> String {
        do {
            return try String(contentsOf: URL(fileURLWithPath: configFilePath), encoding: .utf8)
        } catch {
            throw HooksError.fileSystemError(
                reason: "Could not read \(configFilePath): \(error.localizedDescription)"
            )
        }
    }

    private func writeConfig(_ contents: String) throws {
        let directory = URL(fileURLWithPath: configFilePath).deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(to: URL(fileURLWithPath: configFilePath), atomically: true, encoding: .utf8)
    }

    private func createBackupIfNeeded() throws {
        let backupPath = "\(configFilePath).cocxy-backup"
        guard fileManager.fileExists(atPath: configFilePath),
              !fileManager.fileExists(atPath: backupPath) else {
            return
        }
        try fileManager.copyItem(
            at: URL(fileURLWithPath: configFilePath),
            to: URL(fileURLWithPath: backupPath)
        )
    }

    static var hookEvents: [String] {
        eventMappings.map(\.cocxyEvent)
    }

    static func installedEvents(in contents: String) -> [String] {
        hookEvents.filter { event in
            let rawEventToken = #""hook_event_name":"\#(event)""#
            let escapedEventToken = #"\"hook_event_name\":\"\#(event)\""#
            return contents.contains("COCXY_HOOK_AGENT=rovo")
                && contents.contains("hook-handler")
                && (contents.contains(rawEventToken) || contents.contains(escapedEventToken))
        }
    }

    static func reconciledConfig(_ existing: String) -> String {
        let normalizedExisting = removingManagedBlock(from: existing).trimmingCharacters(in: .newlines)

        if normalizedExisting.isEmpty {
            return fullConfigTemplate()
        }

        var lines = normalizedExisting.components(separatedBy: .newlines)
        if let eventsIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "events:" }) {
            let managedIndentation = leadingWhitespace(in: lines[eventsIndex]) + "  "
            lines.insert(
                contentsOf: managedEventsBlock(indentation: managedIndentation).components(separatedBy: .newlines),
                at: eventsIndex + 1
            )
            return lines.joined(separator: "\n") + "\n"
        }

        if let eventHooksIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "eventHooks:" }) {
            let eventsIndentation = leadingWhitespace(in: lines[eventHooksIndex]) + "  "
            let insertion = ["\(eventsIndentation)events:"]
                + managedEventsBlock(indentation: eventsIndentation + "  ").components(separatedBy: .newlines)
            lines.insert(contentsOf: insertion, at: eventHooksIndex + 1)
            return lines.joined(separator: "\n") + "\n"
        }

        return normalizedExisting + "\n\n" + fullConfigTemplate()
    }

    static func removingManagedBlock(from contents: String) -> String {
        let lines = contents.components(separatedBy: .newlines)
        var output: [String] = []
        var insideManagedBlock = false

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == beginMarker {
                insideManagedBlock = true
                continue
            }
            if line.trimmingCharacters(in: .whitespaces) == endMarker {
                insideManagedBlock = false
                continue
            }
            if !insideManagedBlock {
                output.append(line)
            }
        }

        while output.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            output.removeLast()
        }

        return output.joined(separator: "\n") + "\n"
    }

    static func fullConfigTemplate() -> String {
        """
        eventHooks:
          events:
        \(managedEventsBlock(indentation: "    "))
        """
    }

    static func managedEventsBlock(indentation: String) -> String {
        var lines = ["\(indentation)\(beginMarker)"]
        for mapping in eventMappings {
            lines.append("\(indentation)- name: \(mapping.rovoEvent)")
            lines.append("\(indentation)  commands:")
            lines.append("\(indentation)    - command: \(yamlDoubleQuoted(command(for: mapping.cocxyEvent)))")
        }
        lines.append("\(indentation)\(endMarker)")
        return lines.joined(separator: "\n")
    }

    static func command(for cocxyEvent: String) -> String {
        let payload = #"{"hook_event_name":"\#(cocxyEvent)","agent_type":"rovo-dev"}"#
        return "printf %s \(ClaudeSettingsManager.shellSingleQuoted(payload)) | COCXY_CLAUDE_HOOKS=1 COCXY_HOOK_AGENT=rovo \(ClaudeSettingsManager.cocxyHookCommand)"
    }

    private static func yamlDoubleQuoted(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func leadingWhitespace(in line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }
}
