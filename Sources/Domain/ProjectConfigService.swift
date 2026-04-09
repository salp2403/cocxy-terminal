// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectConfigService.swift - Per-project config loading from .cocxy.toml.

import Foundation

// MARK: - Project Config

/// Partial configuration override loaded from a `.cocxy.toml` file.
///
/// All fields are optional. Only non-nil values override the global
/// `CocxyConfig`. This struct represents the v1 scope: UI-level
/// overrides that do not require recreating the terminal engine.
///
/// Supported overrides:
/// - Appearance: font-size, padding, opacity, blur
/// - Agent detection: extra launch patterns
/// - Keybindings: per-project shortcut overrides
///
/// Engine-level settings (theme, shell, cursor-style) are planned
/// for v2 and intentionally excluded here.
struct ProjectConfig: Codable, Equatable, Sendable {

    // MARK: - Appearance Overrides

    /// Font size override. Valid range: [6.0, 72.0].
    let fontSize: Double?

    /// Window padding override. Must be >= 0.
    let windowPadding: Double?

    /// Horizontal padding override. Overrides windowPadding for X axis.
    let windowPaddingX: Double?

    /// Vertical padding override. Overrides windowPadding for Y axis.
    let windowPaddingY: Double?

    /// Background opacity override. Valid range: [0.1, 1.0].
    let backgroundOpacity: Double?

    /// Background blur radius override. Valid range: [0, 100].
    let backgroundBlurRadius: Double?

    // MARK: - Agent Detection Overrides

    /// Additional launch patterns for agent detection.
    /// These are ADDED to the global patterns, not replacing them.
    let agentDetectionExtraPatterns: [String]?

    // MARK: - Keybinding Overrides

    /// Per-project keybinding overrides. Keys are TOML key names
    /// (e.g., "new-tab"), values are shortcut strings (e.g., "cmd+shift+t").
    /// Only specified keys override; unspecified keys keep global values.
    let keybindingOverrides: [String: String]?

    /// Whether all fields are nil (no overrides).
    var isEmpty: Bool {
        fontSize == nil && windowPadding == nil && windowPaddingX == nil
            && windowPaddingY == nil && backgroundOpacity == nil
            && backgroundBlurRadius == nil && agentDetectionExtraPatterns == nil
            && keybindingOverrides == nil
    }

    // MARK: - Initialization

    init(
        fontSize: Double? = nil,
        windowPadding: Double? = nil,
        windowPaddingX: Double? = nil,
        windowPaddingY: Double? = nil,
        backgroundOpacity: Double? = nil,
        backgroundBlurRadius: Double? = nil,
        agentDetectionExtraPatterns: [String]? = nil,
        keybindingOverrides: [String: String]? = nil
    ) {
        self.fontSize = fontSize
        self.windowPadding = windowPadding
        self.windowPaddingX = windowPaddingX
        self.windowPaddingY = windowPaddingY
        self.backgroundOpacity = backgroundOpacity
        self.backgroundBlurRadius = backgroundBlurRadius
        self.agentDetectionExtraPatterns = agentDetectionExtraPatterns
        self.keybindingOverrides = keybindingOverrides
    }
}

// MARK: - Project Config Service

/// Finds and parses `.cocxy.toml` files for per-project configuration.
///
/// Walks up from a directory to find the nearest `.cocxy.toml`,
/// stopping at the user's home directory. Parses the file using
/// `TOMLParser` and returns a `ProjectConfig` with validated values.
final class ProjectConfigService {

    private let parser = TOMLParser()

    // MARK: - Public API

    /// Parses TOML content into a ProjectConfig.
    ///
    /// Returns nil if the content is empty, whitespace-only, malformed,
    /// or produces a config with all fields nil (nothing to override).
    func parse(_ tomlContent: String) -> ProjectConfig? {
        let trimmed = tomlContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parsed: [String: TOMLValue]
        do {
            parsed = try parser.parse(tomlContent)
        } catch {
            return nil
        }

        // Extract root-level appearance overrides
        let fontSize = doubleValue(parsed["font-size"]).map { clamp($0, min: 6.0, max: 72.0) }
        let windowPadding = doubleValue(parsed["window-padding"]).map { max(0.0, $0) }
        let windowPaddingX = doubleValue(parsed["window-padding-x"]).map { max(0.0, $0) }
        let windowPaddingY = doubleValue(parsed["window-padding-y"]).map { max(0.0, $0) }
        let backgroundOpacity = doubleValue(parsed["background-opacity"]).map { clamp($0, min: 0.1, max: 1.0) }
        let backgroundBlurRadius = doubleValue(parsed["background-blur-radius"]).map { clamp($0, min: 0.0, max: 100.0) }

        // Extract [agent-detection] table
        let agentTable = extractTable("agent-detection", from: parsed)
        let extraPatterns = extractStringArray(agentTable["extra-launch-patterns"])

        // Extract [keybindings] table
        let keybindingsTable = extractTable("keybindings", from: parsed)
        let keybindingOverrides: [String: String]? = keybindingsTable.isEmpty ? nil : {
            var result: [String: String] = [:]
            for (key, value) in keybindingsTable {
                if let str = stringValue(value) {
                    result[key] = str
                }
            }
            return result.isEmpty ? nil : result
        }()

        // Return nil if every field is nil (nothing to override)
        let config = ProjectConfig(
            fontSize: fontSize,
            windowPadding: windowPadding,
            windowPaddingX: windowPaddingX,
            windowPaddingY: windowPaddingY,
            backgroundOpacity: backgroundOpacity,
            backgroundBlurRadius: backgroundBlurRadius,
            agentDetectionExtraPatterns: extraPatterns,
            keybindingOverrides: keybindingOverrides
        )

        if config.isEmpty {
            return nil
        }

        return config
    }

    /// Finds and loads a `.cocxy.toml` from the given directory or its parents.
    ///
    /// Stops searching at the user's home directory. Returns nil if no
    /// `.cocxy.toml` is found anywhere in the traversal path.
    func loadConfig(for directory: URL) -> ProjectConfig? {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        var current = directory.standardizedFileURL

        while true {
            let configFile = current.appendingPathComponent(".cocxy.toml")

            if fileManager.fileExists(atPath: configFile.path) {
                guard let content = try? String(contentsOf: configFile, encoding: .utf8) else {
                    return nil
                }
                return parse(content)
            }

            // Stop at home directory (don't traverse above it)
            if current.path == homeDir.path {
                return nil
            }

            let parent = current.deletingLastPathComponent().standardizedFileURL

            // Stop at filesystem root (parent == current)
            if parent.path == current.path {
                return nil
            }

            current = parent
        }
    }

    /// Returns the path to the nearest `.cocxy.toml`, or nil if not found.
    ///
    /// Uses the same directory traversal as `loadConfig(for:)` but returns
    /// the file path for use by `ProjectConfigWatcher`.
    func findConfigPath(for directory: URL) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        var current = directory.standardizedFileURL

        while true {
            let configPath = current.appendingPathComponent(".cocxy.toml")
            if FileManager.default.fileExists(atPath: configPath.path) {
                return configPath.path
            }

            if current.path == home.path { break }

            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    // MARK: - Value Extractors

    /// Extracts a string from a TOML value, returning nil for non-string values.
    private func stringValue(_ value: TOMLValue?) -> String? {
        guard case .string(let content) = value else { return nil }
        return content
    }

    /// Extracts a double from a TOML value.
    ///
    /// Accepts both `.float` and `.integer` TOML values, converting integers
    /// to doubles transparently.
    private func doubleValue(_ value: TOMLValue?) -> Double? {
        switch value {
        case .float(let content):
            return content
        case .integer(let content):
            return Double(content)
        default:
            return nil
        }
    }

    /// Extracts a table from the parsed TOML by section name.
    private func extractTable(
        _ sectionName: String,
        from parsed: [String: TOMLValue]
    ) -> [String: TOMLValue] {
        guard case .table(let table) = parsed[sectionName] else { return [:] }
        return table
    }

    /// Extracts an array of strings from a TOML value.
    ///
    /// Returns nil if the value is not an array or contains non-string elements.
    private func extractStringArray(_ value: TOMLValue?) -> [String]? {
        guard case .array(let items) = value else { return nil }
        var result: [String] = []
        for item in items {
            guard case .string(let str) = item else { return nil }
            result.append(str)
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Validation Helpers

    /// Clamps a comparable value to a range.
    private func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.min(Swift.max(value, min), max)
    }
}
