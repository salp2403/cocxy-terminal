// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemeProviding.swift - Contract for the theme engine.

import Foundation
import Combine

// MARK: - Theme Providing Protocol

/// Manages visual themes for both terminal surfaces and Cocxy UI elements.
///
/// The theme system has three layers (ADR-007):
/// 1. **Built-in themes** — compiled into the app, always available.
/// 2. **Custom user themes** — TOML files in `~/.config/cocxy/themes/`.
/// 3. **Ghostty import** — reads existing Ghostty themes as fallback.
///
/// When a Ghostty theme is imported, it only provides ANSI colors. The UI
/// colors (tab backgrounds, badges, etc.) are derived automatically from
/// the foreground and background colors.
///
/// Supports automatic dark/light switching based on macOS appearance changes.
///
/// - SeeAlso: ADR-007 (Theme system)
/// - SeeAlso: ARCHITECTURE.md Section 7.6
@MainActor
protocol ThemeProviding: AnyObject {

    /// The currently active theme.
    var activeTheme: Theme { get }

    /// All available themes (built-in + custom + imported).
    var availableThemes: [ThemeMetadata] { get }

    /// Applies a theme by name.
    ///
    /// - Parameter themeName: The name of the theme to apply. Must match a
    ///   name from `availableThemes`.
    /// - Throws: `ThemeError.themeNotFound` if no theme with that name exists.
    func apply(themeName: String) throws

    /// Publisher that emits the new theme whenever it changes.
    ///
    /// Changes can be triggered by:
    /// - Explicit call to `apply(themeName:)`.
    /// - macOS appearance change (dark <-> light) when auto-switch is enabled.
    /// - Hot-reload of a custom theme file on disk.
    var themeChangedPublisher: AnyPublisher<Theme, Never> { get }
}

// MARK: - Theme Model

/// A fully resolved theme ready to be applied to the UI.
struct Theme: Sendable {
    /// Metadata about the theme (name, variant, source).
    let metadata: ThemeMetadata
    /// Resolved color palette for all UI elements and terminal colors.
    let palette: ThemePalette
}

/// Descriptive metadata for a theme.
struct ThemeMetadata: Codable, Sendable, Equatable {
    /// Display name (e.g., "Catppuccin Mocha").
    let name: String
    /// Whether this is a dark or light theme.
    let variant: ThemeVariant
    /// Author of the theme.
    let author: String?
    /// Where the theme was loaded from.
    let source: ThemeSource
}

/// Dark or light theme variant.
enum ThemeVariant: String, Codable, Sendable {
    case dark
    case light
}

/// Origin of a theme definition.
enum ThemeSource: Codable, Sendable, Equatable {
    /// Compiled into the application binary.
    case builtIn
    /// Imported from a Ghostty theme file.
    case ghosttyImport
    /// User-defined theme at the given file URL.
    case custom(URL)
}

// MARK: - Theme Palette

/// Complete color palette for a theme.
///
/// Colors are represented as hex strings (e.g., "#1e1e2e") rather than
/// `NSColor` to keep the domain layer free of AppKit dependencies.
/// The UI layer is responsible for converting hex strings to `NSColor`.
///
/// This follows ADR-002: "A ViewModel NEVER imports AppKit."
struct ThemePalette: Sendable, Equatable {
    // MARK: Base colors

    /// Main background color of the terminal.
    let background: String
    /// Main foreground (text) color.
    let foreground: String
    /// Cursor color.
    let cursor: String
    /// Background color for selected text.
    let selectionBackground: String
    /// Foreground color for selected text.
    let selectionForeground: String

    // MARK: Tab bar colors

    /// Background of the active (focused) tab.
    let tabActiveBackground: String
    /// Text color of the active tab.
    let tabActiveForeground: String
    /// Background of inactive tabs.
    let tabInactiveBackground: String
    /// Text color of inactive tabs.
    let tabInactiveForeground: String

    // MARK: Agent badge colors

    /// Badge color for "agent needs attention" state.
    let badgeAttention: String
    /// Badge color for "agent finished" state.
    let badgeCompleted: String
    /// Badge color for "agent error" state.
    let badgeError: String
    /// Badge color for "agent working" state.
    let badgeWorking: String

    // MARK: ANSI terminal colors

    /// Standard ANSI colors (16 total: 8 normal + 8 bright).
    ///
    /// Order: black, red, green, yellow, blue, magenta, cyan, white,
    /// then their bright variants in the same order.
    let ansiColors: [String]
}

// MARK: - Theme Errors

/// Errors that can occur during theme operations.
enum ThemeError: Error, Sendable {
    /// No theme with the given name was found.
    case themeNotFound(name: String)
    /// The theme file could not be parsed.
    case parseFailed(path: String, reason: String)
    /// The theme has invalid or missing color values.
    case invalidColor(key: String, value: String)
}
