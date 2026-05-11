// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginManifest.swift - Parser and model for plugin manifest.toml files.

import Foundation
import CocxyCommandSignatures

// MARK: - Plugin Manifest

/// Describes a Cocxy plugin from its `cocxy-plugin.toml` or legacy
/// `manifest.toml` file.
///
/// Plugins are stored as directories in `~/.cocxy/plugins/`.
/// Each plugin directory contains a manifest with metadata
/// and optionally scripts that respond to terminal events.
///
/// ## Directory Layout
///
/// ```
/// ~/.cocxy/plugins/
/// └── my-plugin/
///     ├── cocxy-plugin.toml
///     ├── on-session-start.sh    (optional)
///     ├── on-agent-detected.sh   (optional)
///     ├── on-command-complete.sh  (optional)
///     └── README.md              (optional)
/// ```
struct PluginManifest: Identifiable, Codable, Equatable, Sendable {

    /// Legacy plugin manifest filename kept for backward compatibility.
    static let legacyManifestFileName = "manifest.toml"

    /// Marketplace plugin manifest filename used by decentralized plugin repos.
    static let marketplaceManifestFileName = "cocxy-plugin.toml"

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

    /// Manifest filename used on disk.
    var manifestFileName: String = Self.legacyManifestFileName

    /// Source repository URL declared by marketplace plugins.
    var repositoryURL: String?

    /// Optional homepage URL declared by the plugin.
    var homepageURL: String?

    /// Optional license identifier declared by the plugin.
    var license: String?

    /// Capabilities requested by this plugin.
    var capabilities: Set<PluginCapability> = []

    /// Optional signature metadata. Unsigned plugins are allowed, but surfaced.
    var signature: PluginSignature?

    /// Returns a copy with its directory path updated after staging/install.
    func relocated(to directoryPath: String) -> PluginManifest {
        PluginManifest(
            id: id,
            name: name,
            description: description,
            version: version,
            author: author,
            minCocxyVersion: minCocxyVersion,
            events: events,
            directoryPath: directoryPath,
            manifestFileName: manifestFileName,
            repositoryURL: repositoryURL,
            homepageURL: homepageURL,
            license: license,
            capabilities: capabilities,
            signature: signature
        )
    }
}

// MARK: - Plugin Capability

/// Explicit capabilities a plugin may request in `cocxy-plugin.toml`.
enum PluginCapability: String, Codable, Sendable, CaseIterable, Hashable {
    case filesystemRead = "filesystem-read"
    case filesystemWrite = "filesystem-write"
    case environmentRead = "environment-read"
    case processSpawn = "process-spawn"
    case networkClient = "network-client"
}

// MARK: - Plugin Signature

/// Optional signature metadata for decentralized plugins.
struct PluginSignature: Codable, Equatable, Sendable {
    let algorithm: String
    let keyID: String?
    let value: String
    let author: String?
    let timestamp: Date?
    let payloadSHA256: String?

    func signedArtifact() -> SignedArtifact? {
        guard let algorithm = SignatureAlgorithm(rawValue: algorithm),
              let keyID,
              let author,
              let timestamp,
              let payloadSHA256
        else {
            return nil
        }
        return SignedArtifact(
            algorithm: algorithm,
            keyID: keyID,
            author: author,
            timestamp: timestamp,
            payloadSHA256: payloadSHA256,
            signature: value
        )
    }
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
    case richInputSubmit = "rich-input-submit"
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
        let manifestFileName = URL(fileURLWithPath: filePath).lastPathComponent
        return try parse(
            content: content,
            directoryPath: directoryPath,
            manifestFileName: manifestFileName
        )
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
        directoryPath: String,
        manifestFileName: String = PluginManifest.legacyManifestFileName
    ) throws -> PluginManifest {
        let values = parseToml(content)

        guard let name = values["name"] else {
            throw PluginManifestError.missingRequiredField("name")
        }

        let directoryName = values["id"] ?? URL(fileURLWithPath: directoryPath).lastPathComponent

        let eventsRaw = parseStringArray(values["events"])

        let events = eventsRaw.compactMap { PluginEvent(rawValue: $0) }
        let capabilities = Set(parseStringArray(values["capabilities"]).compactMap {
            PluginCapability(rawValue: $0)
        })
        let signatureValue = values["signature"]
        let signature = signatureValue.map {
            PluginSignature(
                algorithm: values["signature-algorithm"] ?? "unknown",
                keyID: values["signature-key-id"],
                value: $0,
                author: values["signature-author"],
                timestamp: values["signature-timestamp"].flatMap {
                    ISO8601DateFormatter.cocxySignature.date(from: $0)
                },
                payloadSHA256: values["signature-payload-sha256"]
            )
        }

        return PluginManifest(
            id: directoryName,
            name: name,
            description: values["description"] ?? "",
            version: values["version"] ?? "0.0.0",
            author: values["author"] ?? "Unknown",
            minCocxyVersion: values["min-cocxy-version"],
            events: events,
            directoryPath: directoryPath,
            manifestFileName: manifestFileName,
            repositoryURL: values["repository"],
            homepageURL: values["homepage"],
            license: values["license"],
            capabilities: capabilities,
            signature: signature
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

    private static func parseStringArray(_ rawValue: String?) -> [String] {
        guard let rawValue else { return [] }
        return rawValue
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            .filter { !$0.isEmpty }
    }
}
