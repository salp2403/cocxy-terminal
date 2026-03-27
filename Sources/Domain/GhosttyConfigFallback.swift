// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyConfigFallback.swift - Reads Ghostty config as fallback when no cocxy.toml exists.

import Foundation

// MARK: - Ghostty Config Fallback

/// Reads appearance settings from Ghostty's native config file.
///
/// When a user has Ghostty configured but hasn't created a Cocxy config,
/// this fallback imports their preferences so the terminal looks familiar
/// on first launch. Only appearance-related keys are read:
///
/// - `font-family` -> appearance.fontFamily
/// - `font-size` -> appearance.fontSize
/// - `theme` -> appearance.theme
/// - `cursor-style` -> terminal.cursorStyle
///
/// All other Cocxy settings remain at their defaults.
///
/// ## File format
///
/// Ghostty uses a simple `key = value` format (no sections, no TOML):
/// ```
/// font-family = "JetBrains Mono"
/// font-size = 14
/// theme = catppuccin-mocha
/// cursor-style = block
/// ```
///
/// - SeeAlso: `ConfigService` which calls this fallback during `reload()`
/// - SeeAlso: `GhosttyThemeImporter` for importing Ghostty theme files
enum GhosttyConfigFallback {

    /// Default path to the Ghostty config file.
    static let defaultConfigPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/ghostty/config"
    }()

    /// Result of reading the Ghostty config fallback.
    ///
    /// Contains only the keys that map to Cocxy appearance settings.
    /// All values are optional — nil means the key was absent or unparseable.
    struct FallbackValues {
        var fontFamily: String?
        var fontSize: Double?
        var theme: String?
        var cursorStyle: String?

        /// Whether any usable values were found.
        var isEmpty: Bool {
            fontFamily == nil && fontSize == nil && theme == nil && cursorStyle == nil
        }
    }

    // MARK: - Public API

    /// Reads the Ghostty config and extracts appearance values.
    ///
    /// Returns `nil` if the file does not exist or is empty.
    /// Invalid values for individual keys are silently skipped.
    ///
    /// - Parameter path: Path to the Ghostty config file.
    ///   Defaults to `~/.config/ghostty/config`.
    /// - Returns: Extracted values, or nil if the file does not exist.
    static func read(from path: String = defaultConfigPath) -> FallbackValues? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let parsed = parseKeyValues(content)
        guard !parsed.isEmpty else { return nil }

        var values = FallbackValues()

        if let fontFamily = parsed["font-family"] {
            values.fontFamily = fontFamily.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        if let fontSizeStr = parsed["font-size"], let fontSize = Double(fontSizeStr) {
            values.fontSize = fontSize
        }

        if let theme = parsed["theme"] {
            values.theme = theme
        }

        if let cursorStyle = parsed["cursor-style"] {
            values.cursorStyle = cursorStyle
        }

        return values.isEmpty ? nil : values
    }

    /// Applies Ghostty fallback values to a default Cocxy config.
    ///
    /// Only overrides values that were found in the Ghostty config.
    /// All other settings remain at Cocxy defaults.
    ///
    /// - Parameter fallback: The values read from Ghostty's config.
    /// - Returns: A `CocxyConfig` with the fallback values applied.
    static func applyToDefaults(_ fallback: FallbackValues) -> CocxyConfig {
        let defaults = CocxyConfig.defaults
        let appearance = AppearanceConfig(
            theme: fallback.theme ?? defaults.appearance.theme,
            fontFamily: fallback.fontFamily ?? defaults.appearance.fontFamily,
            fontSize: fallback.fontSize.map { max(6, min(72, $0)) }
                ?? defaults.appearance.fontSize,
            tabPosition: defaults.appearance.tabPosition,
            windowPadding: defaults.appearance.windowPadding,
            windowPaddingX: defaults.appearance.windowPaddingX,
            windowPaddingY: defaults.appearance.windowPaddingY,
            backgroundOpacity: defaults.appearance.backgroundOpacity,
            backgroundBlurRadius: defaults.appearance.backgroundBlurRadius
        )

        return CocxyConfig(
            general: defaults.general,
            appearance: appearance,
            terminal: defaults.terminal,
            agentDetection: defaults.agentDetection,
            notifications: defaults.notifications,
            quickTerminal: defaults.quickTerminal,
            keybindings: defaults.keybindings,
            sessions: defaults.sessions
        )
    }

    // MARK: - Parsing

    /// Parses Ghostty's key=value config format into a dictionary.
    ///
    /// Handles:
    /// - Leading/trailing whitespace
    /// - Inline comments (# after value)
    /// - Blank lines and comment-only lines
    /// - Quoted and unquoted values
    ///
    /// Does NOT handle: sections, arrays, or nested values.
    private static func parseKeyValues(_ content: String) -> [String: String] {
        var result: [String: String] = [:]

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments.
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            // Split on first "=" only.
            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }

            let key = trimmed[trimmed.startIndex..<equalsIndex]
                .trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespaces)

            // Strip inline comments (but not inside quoted strings).
            if !value.hasPrefix("\"") {
                if let commentIndex = value.firstIndex(of: "#") {
                    value = String(value[value.startIndex..<commentIndex])
                        .trimmingCharacters(in: .whitespaces)
                }
            }

            guard !key.isEmpty, !value.isEmpty else { continue }
            result[key] = value
        }

        return result
    }
}
