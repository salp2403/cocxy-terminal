// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemeEngine.swift - Theme loading, application and auto-switch.

import Foundation
@preconcurrency import Combine

// MARK: - Theme Engine

/// Concrete implementation of `ThemeProviding`.
///
/// Manages built-in themes, custom user themes from TOML files, and
/// automatic import from Ghostty theme configuration. Supports auto-switch
/// between dark and light variants based on macOS appearance changes.
///
/// Built-in themes:
/// - Catppuccin Mocha (dark)
/// - Catppuccin Latte (light)
/// - One Dark (dark)
/// - Solarized Dark (dark)
/// - Solarized Light (light)
/// - Dracula (dark)
///
/// - SeeAlso: ADR-007 (Theme system)
/// - SeeAlso: `ThemeProviding` protocol
final class ThemeEngineImpl: ThemeProviding {

    // MARK: - Properties

    /// The currently active theme.
    private(set) var activeTheme: Theme

    /// All available themes (built-in + custom).
    private(set) var availableThemes: [ThemeMetadata]

    /// Publisher that emits the new theme on changes.
    var themeChangedPublisher: AnyPublisher<Theme, Never> {
        themeSubject.eraseToAnyPublisher()
    }

    /// Internal storage for all loaded themes keyed by name.
    private var themesByName: [String: Theme]

    /// Combine subject for theme change notifications.
    private let themeSubject: CurrentValueSubject<Theme, Never>

    /// File provider for custom themes.
    private let themeFileProvider: ThemeFileProviding

    // MARK: - Initialization

    /// Creates a ThemeEngine that loads built-in themes and custom themes.
    ///
    /// - Parameter themeFileProvider: Source of custom theme files.
    ///   Defaults to `DiskThemeFileProvider` for production use.
    init(themeFileProvider: ThemeFileProviding = DiskThemeFileProvider()) {
        self.themeFileProvider = themeFileProvider

        // Load built-in themes first
        let builtInThemes = ThemeEngineImpl.loadBuiltInThemes()
        var allThemes = builtInThemes

        // Load custom themes
        let customThemes = ThemeEngineImpl.loadCustomThemes(from: themeFileProvider)
        allThemes.append(contentsOf: customThemes)

        // Build lookup dictionary
        var themesByName: [String: Theme] = [:]
        for theme in allThemes {
            themesByName[theme.metadata.name] = theme
        }
        self.themesByName = themesByName
        self.availableThemes = allThemes.map(\.metadata)

        // Default active theme: Catppuccin Mocha
        guard let defaultTheme = themesByName["Catppuccin Mocha"] ?? allThemes.first else {
            fatalError("ThemeEngine requires at least one built-in theme")
        }
        self.activeTheme = defaultTheme
        self.themeSubject = CurrentValueSubject(defaultTheme)
    }

    // MARK: - Theme Application

    /// Applies a theme by name.
    ///
    /// - Parameter themeName: The display name of the theme.
    /// - Throws: `ThemeError.themeNotFound` if no theme with that name exists.
    func apply(themeName: String) throws {
        let theme = try themeByName(themeName)
        activeTheme = theme
        themeSubject.send(theme)
    }

    /// Returns a theme by name, with fuzzy matching.
    ///
    /// Accepts both display names ("Catppuccin Mocha") and config names
    /// ("catppuccin-mocha"). Tries exact match first, then falls back to
    /// normalized comparison (lowercased, hyphens and spaces removed).
    ///
    /// - Parameter name: The theme name in any format.
    /// - Returns: The fully resolved theme.
    /// - Throws: `ThemeError.themeNotFound` if no theme matches.
    func themeByName(_ name: String) throws -> Theme {
        // Exact match first.
        if let theme = themesByName[name] {
            return theme
        }
        // Normalized fallback: "catppuccin-mocha" matches "Catppuccin Mocha".
        let normalized = Self.normalizeThemeName(name)
        for (key, theme) in themesByName {
            if Self.normalizeThemeName(key) == normalized {
                return theme
            }
        }
        throw ThemeError.themeNotFound(name: name)
    }

    /// Normalizes a theme name for fuzzy comparison.
    ///
    /// Strips hyphens, underscores, and spaces, then lowercases the result.
    /// "Catppuccin Mocha", "catppuccin-mocha", and "catppuccin_mocha" all
    /// normalize to "catppuccinmocha".
    private static func normalizeThemeName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    // MARK: - Built-In Theme Loading

    /// Loads all 6 built-in themes defined in ADR-007.
    private static func loadBuiltInThemes() -> [Theme] {
        [
            catppuccinMocha(),
            catppuccinLatte(),
            oneDark(),
            solarizedDark(),
            solarizedLight(),
            dracula()
        ]
    }

    // MARK: - Custom Theme Loading

    /// Loads custom themes from the file provider.
    ///
    /// Invalid themes are silently skipped to avoid breaking the engine.
    private static func loadCustomThemes(from provider: ThemeFileProviding) -> [Theme] {
        var themes: [Theme] = []

        let themesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/themes")

        for (filename, content) in provider.listCustomThemeFiles() {
            do {
                var theme = try ThemeTomlParser.parse(content)
                let fileURL = themesDir.appendingPathComponent(filename)
                let updatedMetadata = ThemeMetadata(
                    name: theme.metadata.name,
                    variant: theme.metadata.variant,
                    author: theme.metadata.author,
                    source: .custom(fileURL)
                )
                theme = Theme(metadata: updatedMetadata, palette: theme.palette)
                themes.append(theme)
            } catch {
                // Skip invalid theme files without crashing
                continue
            }
        }

        return themes
    }

    // MARK: - Built-In Theme Definitions

    /// Catppuccin Mocha (dark) - catppuccin.com
    private static func catppuccinMocha() -> Theme {
        let palette = ThemePalette(
            background: "#1e1e2e",
            foreground: "#cdd6f4",
            cursor: "#f5e0dc",
            selectionBackground: "#585b70",
            selectionForeground: "#cdd6f4",
            tabActiveBackground: "#1e1e2e",
            tabActiveForeground: "#cdd6f4",
            tabInactiveBackground: "#181825",
            tabInactiveForeground: "#6c7086",
            badgeAttention: "#f9e2af",
            badgeCompleted: "#a6e3a1",
            badgeError: "#f38ba8",
            badgeWorking: "#89b4fa",
            ansiColors: [
                "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af",
                "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
                "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af",
                "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"
            ]
        )

        return Theme(
            metadata: ThemeMetadata(
                name: "Catppuccin Mocha",
                variant: .dark,
                author: "Catppuccin",
                source: .builtIn
            ),
            palette: palette
        )
    }

    /// Catppuccin Latte (light) - catppuccin.com
    private static func catppuccinLatte() -> Theme {
        let palette = ThemePalette(
            background: "#eff1f5",
            foreground: "#4c4f69",
            cursor: "#dc8a78",
            selectionBackground: "#acb0be",
            selectionForeground: "#4c4f69",
            tabActiveBackground: "#eff1f5",
            tabActiveForeground: "#4c4f69",
            tabInactiveBackground: "#e6e9ef",
            tabInactiveForeground: "#9ca0b0",
            badgeAttention: "#df8e1d",
            badgeCompleted: "#40a02b",
            badgeError: "#d20f39",
            badgeWorking: "#1e66f5",
            ansiColors: [
                "#5c5f77", "#d20f39", "#40a02b", "#df8e1d",
                "#1e66f5", "#ea76cb", "#179299", "#acb0be",
                "#6c6f85", "#d20f39", "#40a02b", "#df8e1d",
                "#1e66f5", "#ea76cb", "#179299", "#bcc0cc"
            ]
        )

        return Theme(
            metadata: ThemeMetadata(
                name: "Catppuccin Latte",
                variant: .light,
                author: "Catppuccin",
                source: .builtIn
            ),
            palette: palette
        )
    }

    /// One Dark - Atom editor
    private static func oneDark() -> Theme {
        let palette = ThemePalette(
            background: "#282c34",
            foreground: "#abb2bf",
            cursor: "#528bff",
            selectionBackground: "#3e4451",
            selectionForeground: "#abb2bf",
            tabActiveBackground: "#282c34",
            tabActiveForeground: "#abb2bf",
            tabInactiveBackground: "#21252b",
            tabInactiveForeground: "#636d83",
            badgeAttention: "#e5c07b",
            badgeCompleted: "#98c379",
            badgeError: "#e06c75",
            badgeWorking: "#61afef",
            ansiColors: [
                "#282c34", "#e06c75", "#98c379", "#e5c07b",
                "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
                "#545862", "#e06c75", "#98c379", "#e5c07b",
                "#61afef", "#c678dd", "#56b6c2", "#c8ccd4"
            ]
        )

        return Theme(
            metadata: ThemeMetadata(
                name: "One Dark",
                variant: .dark,
                author: "Atom",
                source: .builtIn
            ),
            palette: palette
        )
    }

    /// Solarized Dark - ethanschoonover.com
    private static func solarizedDark() -> Theme {
        let palette = ThemePalette(
            background: "#002b36",
            foreground: "#839496",
            cursor: "#93a1a1",
            selectionBackground: "#073642",
            selectionForeground: "#839496",
            tabActiveBackground: "#002b36",
            tabActiveForeground: "#839496",
            tabInactiveBackground: "#001e26",
            tabInactiveForeground: "#586e75",
            badgeAttention: "#b58900",
            badgeCompleted: "#859900",
            badgeError: "#dc322f",
            badgeWorking: "#268bd2",
            ansiColors: [
                "#073642", "#dc322f", "#859900", "#b58900",
                "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                "#002b36", "#cb4b16", "#586e75", "#657b83",
                "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"
            ]
        )

        return Theme(
            metadata: ThemeMetadata(
                name: "Solarized Dark",
                variant: .dark,
                author: "Ethan Schoonover",
                source: .builtIn
            ),
            palette: palette
        )
    }

    /// Solarized Light - ethanschoonover.com
    private static func solarizedLight() -> Theme {
        let palette = ThemePalette(
            background: "#fdf6e3",
            foreground: "#657b83",
            cursor: "#586e75",
            selectionBackground: "#eee8d5",
            selectionForeground: "#657b83",
            tabActiveBackground: "#fdf6e3",
            tabActiveForeground: "#657b83",
            tabInactiveBackground: "#eee8d5",
            tabInactiveForeground: "#93a1a1",
            badgeAttention: "#b58900",
            badgeCompleted: "#859900",
            badgeError: "#dc322f",
            badgeWorking: "#268bd2",
            ansiColors: [
                "#073642", "#dc322f", "#859900", "#b58900",
                "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                "#002b36", "#cb4b16", "#586e75", "#657b83",
                "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"
            ]
        )

        return Theme(
            metadata: ThemeMetadata(
                name: "Solarized Light",
                variant: .light,
                author: "Ethan Schoonover",
                source: .builtIn
            ),
            palette: palette
        )
    }

    /// Dracula - draculatheme.com
    private static func dracula() -> Theme {
        let palette = ThemePalette(
            background: "#282a36",
            foreground: "#f8f8f2",
            cursor: "#f8f8f2",
            selectionBackground: "#44475a",
            selectionForeground: "#f8f8f2",
            tabActiveBackground: "#282a36",
            tabActiveForeground: "#f8f8f2",
            tabInactiveBackground: "#21222c",
            tabInactiveForeground: "#6272a4",
            badgeAttention: "#f1fa8c",
            badgeCompleted: "#50fa7b",
            badgeError: "#ff5555",
            badgeWorking: "#8be9fd",
            ansiColors: [
                "#21222c", "#ff5555", "#50fa7b", "#f1fa8c",
                "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5",
                "#d6acff", "#ff92df", "#a4ffff", "#ffffff"
            ]
        )

        return Theme(
            metadata: ThemeMetadata(
                name: "Dracula",
                variant: .dark,
                author: "Dracula Theme",
                source: .builtIn
            ),
            palette: palette
        )
    }
}
