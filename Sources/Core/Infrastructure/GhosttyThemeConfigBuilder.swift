// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GhosttyThemeConfigBuilder.swift - Generates ghostty config from ThemePalette.

import Foundation

// MARK: - Ghostty Theme Config Builder

/// Generates a ghostty-format config file from a `ThemePalette`.
///
/// Ghostty's config format is a simple `key = value` text file.
/// This builder maps our theme palette to ghostty's color keys.
///
/// ## Ghostty color keys
///
/// - `background`: Background color.
/// - `foreground`: Text color.
/// - `cursor-color`: Cursor color.
/// - `selection-background`: Selection highlight.
/// - `selection-foreground`: Selection text.
/// - `palette = N=#RRGGBB`: ANSI palette entries (0-15).
///
/// The generated file is written to a temp location and loaded
/// via `ghostty_config_load_file` before `ghostty_config_finalize`.
///
/// - SeeAlso: `ThemePalette` for color definitions.
/// - SeeAlso: `GhosttyBridge.loadThemePaletteIntoConfig` for usage.
enum GhosttyThemeConfigBuilder {

    /// Ghostty color key names for the 16 ANSI colors.
    /// Ghostty uses "palette = N=#RRGGBB" syntax.
    private static let ansiColorNames = (0...15).map { "palette = \($0)" }

    /// Builds a ghostty-format config string from a theme palette.
    ///
    /// - Parameter palette: The theme palette containing hex color values.
    /// - Returns: A ghostty config file content as a string.
    static func buildConfigString(from palette: ThemePalette) -> String {
        var lines: [String] = []

        // Base colors
        lines.append("background = \(stripHash(palette.background))")
        lines.append("foreground = \(stripHash(palette.foreground))")
        lines.append("cursor-color = \(stripHash(palette.cursor))")
        lines.append("selection-background = \(stripHash(palette.selectionBackground))")
        lines.append("selection-foreground = \(stripHash(palette.selectionForeground))")

        // ANSI palette (0-15)
        for (index, color) in palette.ansiColors.prefix(16).enumerated() {
            lines.append("palette = \(index)=\(stripHash(color))")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the config string to a temporary file in the caches directory.
    ///
    /// Returns the file path on success, or nil on failure.
    ///
    /// - Parameter content: The ghostty config file content.
    /// - Returns: The path to the written file, or nil.
    static func writeTemporaryConfigFile(_ content: String) -> String? {
        let cacheDir: URL
        if let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheDir = dir.appendingPathComponent("com.cocxy.terminal")
        } else {
            return nil
        }

        // Create directory if needed.
        try? FileManager.default.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let filePath = cacheDir.appendingPathComponent("ghostty-theme-config").path

        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: filePath
            )
            return filePath
        } catch {
            NSLog("[GhosttyThemeConfigBuilder] Failed to write config: %@",
                  String(describing: error))
            return nil
        }
    }

    /// Strips the leading '#' from a hex color if present.
    ///
    /// Ghostty accepts colors both with and without '#', but consistency
    /// is better. We strip it since ghostty's format typically uses bare hex.
    private static func stripHash(_ hex: String) -> String {
        if hex.hasPrefix("#") {
            return String(hex.dropFirst())
        }
        return hex
    }
}
