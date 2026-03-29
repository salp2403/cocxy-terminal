// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginManifest.swift - Parser and model for plugin manifest.toml files.

import Foundation

// MARK: - Plugin Manifest

/// Describes a Cocxy plugin from its `manifest.toml` file.
///
/// Plugins are stored as directories in `~/.config/cocxy/plugins/`.
/// Each plugin directory contains a `manifest.toml` with metadata
/// and optionally scripts that respond to terminal events.
///
/// ## Directory Layout
///
/// ```
/// ~/.config/cocxy/plugins/
/// └── my-plugin/
///     ├── manifest.toml
///     ├── on-session-start.sh    (optional)
///     ├── on-agent-detected.sh   (optional)
///     ├── on-command-complete.sh  (optional)
///     └── README.md              (optional)
/// ```
struct PluginManifest: Identifiable, Codable, Equatable, Sendable {

    /// Unique identifier derived from the directory name.
    let id: String

    /// Human-readable name of the plugin.
    let name: String

    /// Brief description of what the plugin does.
    let description: String

    /// Plugin version (semver).
    let version: String

    /// Plugin author.
    let author: String

    /// Minimum Cocxy version required.
    let minCocxyVersion: String?

    /// Events this plugin responds to.
    let events: [PluginEvent]

    /// Absolute path to the plugin directory on disk.
    let directoryPath: String
}

// MARK: - Plugin Event

/// Events that a plugin can respond to.
///
/// Each event maps to a script file in the plugin directory:
/// `on-<event-name>.sh`. The script is executed in a sandbox
/// with environment variables providing event context.
enum PluginEvent: String, Codable, Sendable, CaseIterable {
    case sessionStart = "session-start"
    case sessionEnd = "session-end"
    case agentDetected = "agent-detected"
    case agentStateChanged = "agent-state-changed"
    case commandComplete = "command-complete"
    case tabCreated = "tab-created"
    case tabClosed = "tab-closed"
    case directoryChanged = "directory-changed"

    /// The expected script filename for this event.
    var scriptName: String {
        "on-\(rawValue).sh"
    }
}

// MARK: - Plugin Manifest Error

/// Errors that can occur while parsing a plugin manifest.
enum PluginManifestError: Error, Equatable {
    case fileNotFound(String)
    case parseError(String)
    case missingRequiredField(String)
    case incompatibleVersion(String)
}

// MARK: - Plugin Manifest Parser

/// Parses `manifest.toml` files from plugin directories.
///
/// Uses a minimal TOML parser that handles the subset of TOML
/// used in plugin manifests (flat key-value pairs and arrays).
enum PluginManifestParser {

    /// Parses a manifest.toml file at the given path.
    ///
    /// - Parameters:
    ///   - filePath: Path to the manifest.toml file.
    ///   - directoryPath: Path to the plugin directory.
    /// - Returns: A parsed `PluginManifest`.
    /// - Throws: `PluginManifestError` if the file is missing or malformed.
    static func parse(
        filePath: String,
        directoryPath: String
    ) throws -> PluginManifest {
        let content: String
        do {
            content = try String(contentsOfFile: filePath, encoding: .utf8)
        } catch {
            throw PluginManifestError.fileNotFound(filePath)
        }
        return try parse(content: content, directoryPath: directoryPath)
    }

    /// Parses manifest TOML content from a string.
    ///
    /// - Parameters:
    ///   - content: The TOML content to parse.
    ///   - directoryPath: Path to the plugin directory.
    /// - Returns: A parsed `PluginManifest`.
    /// - Throws: `PluginManifestError` if required fields are missing.
    static func parse(
        content: String,
        directoryPath: String
    ) throws -> PluginManifest {
        let values = parseToml(content)

        guard let name = values["name"] else {
            throw PluginManifestError.missingRequiredField("name")
        }

        let directoryName = URL(fileURLWithPath: directoryPath).lastPathComponent

        let eventsRaw = values["events"]?
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            ?? []

        let events = eventsRaw.compactMap { PluginEvent(rawValue: $0) }

        return PluginManifest(
            id: directoryName,
            name: name,
            description: values["description"] ?? "",
            version: values["version"] ?? "0.0.0",
            author: values["author"] ?? "Unknown",
            minCocxyVersion: values["min-cocxy-version"],
            events: events,
            directoryPath: directoryPath
        )
    }

    /// Minimal TOML parser for flat key-value pairs.
    ///
    /// Handles: `key = "value"`, `key = value`, `key = [...]`.
    /// Does NOT handle nested tables, inline tables, or multi-line values.
    static func parseToml(_ content: String) -> [String: String] {
        var result: [String: String] = [:]

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines, comments, and section headers.
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("[") {
                continue
            }

            // Parse key = value.
            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }

            let key = trimmed[trimmed.startIndex..<equalsIndex]
                .trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespaces)

            // Strip surrounding quotes.
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }

            result[key] = value
        }

        return result
    }
}
