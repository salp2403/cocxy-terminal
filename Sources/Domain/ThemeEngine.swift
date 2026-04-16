// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemeEngine.swift - Theme loading, application and auto-switch.

import Foundation
@preconcurrency import Combine

// MARK: - Theme Engine

/// Concrete implementation of `ThemeProviding`.
///
/// Manages built-in themes and custom user themes from TOML files.
/// Supports auto-switch between dark and light variants based on macOS
/// appearance changes.
///
/// Built-in themes:
/// - Catppuccin Mocha (dark)
/// - Catppuccin Latte (light)
/// - Catppuccin Frappe (dark)
/// - Catppuccin Macchiato (dark)
/// - One Dark (dark)
/// - Solarized Dark (dark)
/// - Solarized Light (light)
/// - Dracula (dark)
/// - Nord (dark)
/// - Gruvbox Dark (dark)
/// - Tokyo Night (dark)
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

    /// Loads all 11 built-in themes.
    private static func loadBuiltInThemes() -> [Theme] {
        [
            catppuccinMocha(),
            catppuccinLatte(),
            catppuccinFrappe(),
            catppuccinMacchiato(),
            oneDark(),
            solarizedDark(),
            solarizedLight(),
            dracula(),
            nord(),
            gruvboxDark(),
            tokyoNight()
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

    /// Catppuccin Frappe (dark) - catppuccin.com
    private static func catppuccinFrappe() -> Theme {
        let palette = ThemePalette(
            background: "#303446",
            foreground: "#c6d0f5",
            cursor: "#f2d5cf",
            selectionBackground: "#626880",
            selectionForeground: "#c6d0f5",
            tabActiveBackground: "#303446",
            tabActiveForeground: "#c6d0f5",
            tabInactiveBackground: "#292c3c",
            tabInactiveForeground: "#737994",
            badgeAttention: "#e5c890",
            badgeCompleted: "#a6d189",
            badgeError: "#e78284",
            badgeWorking: "#8caaee",
            ansiColors: [
                "#414559", "#e78284", "#a6d189", "#e5c890",
                "#8caaee", "#f4b8e4", "#81c8be", "#b5bfe2",
                "#51576d", "#e78284", "#a6d189", "#e5c890",
                "#8caaee", "#f4b8e4", "#81c8be", "#a5adce"
            ]
        )

        return Theme(
            metadata: ThemeMetadata(
                name: "Catppuccin Frappe",
                variant: .dark,
                author: "Catppuccin",
                source: .builtIn
            ),
            palette: palette
        )
    }

    /// Catppuccin Macchiato (dark) - catppuccin.com
    private static func catppuccinMacchiato() -> Theme {
        let palette = ThemePalette(
            background: "#24273a",
            foreground: "#cad3f5",
            cursor: "#f4dbd6",
            selectionBackground: "#5b6078",
            selectionForeground: "#cad3f5",
            tabActiveBackground: "#24273a",
            tabActiveForeground: "#cad3f5",
            tabInactiveBackground: "#1e2030",
            tabInactiveForeground: "#6e738d",
            badgeAttention: "#eed49f",
            badgeCompleted: "#a6da95",
            badgeError: "#ed8796",
            badgeWorking: "#8aadf4",
            ansiColors: [
                "#363a4f", "#ed8796", "#a6da95", "#eed49f",
                "#8aadf4", "#f5bde6", "#8bd5ca", "#b8c0e0",
                "#494d64", "#ed8796", "#a6da95", "#eed49f",
                "#8aadf4", "#f5bde6", "#8bd5ca", "#a5adcb"
            ]
        )

        return Theme(
            metadata: ThemeMetadata(
                name: "Catppuccin Macchiato",
                variant: .dark,
                author: "Catppuccin",
                source: .builtIn
            ),
            palette: palette
        )
    }

    /// Nord (dark) - nordtheme.com
    private static func nord() -> Theme {
        let palette = ThemePalette(
            background: "#2e3440",
            foreground: "#d8dee9",
            cursor: "#d8dee9",
            selectionBackground: "#434c5e",
            selectionForeground: "#d8dee9",
            tabActiveBackground: "#2e3440",
            tabActiveForeground: "#d8dee9",
            tabInactiveBackground: "#272c36",
            tabInactiveForeground: "#4c566a",
            badgeAttention: "#ebcb8b",
            badgeCompleted: "#a3be8c",
            badgeError: "#bf616a",
            badgeWorking: "#81a1c1",
            ansiColors: [
                "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b",
                "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
                "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b",
                "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"
            ]
        )

        return Theme(
            metadata: ThemeMetadata(
                name: "Nord",
                variant: .dark,
                author: "Arctic Ice Studio",
                source: .builtIn
            ),
            palette: palette
        )
    }

    /// Gruvbox Dark - github.com/morhetz/gruvbox
    private static func gruvboxDark() -> Theme {
        let palette = ThemePalette(
            background: "#282828",
            foreground: "#ebdbb2",
            cursor: "#ebdbb2",
            selectionBackground: "#504945",
            selectionForeground: "#ebdbb2",
            tabActiveBackground: "#282828",
            tabActiveForeground: "#ebdbb2",
            tabInactiveBackground: "#1d2021",
            tabInactiveForeground: "#928374",
            badgeAttention: "#fabd2f",
            badgeCompleted: "#b8bb26",
            badgeError: "#fb4934",
            badgeWorking: "#83a598",
            ansiColors: [
                "#282828", "#cc241d", "#98971a", "#d79921",
                "#458588", "#b16286", "#689d6a", "#a89984",
                "#928374", "#fb4934", "#b8bb26", "#fabd2f",
                "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"
            ]
        )

        return Theme(
            metadata: ThemeMetadata(
                name: "Gruvbox Dark",
                variant: .dark,
                author: "Pavel Pertsev",
                source: .builtIn
            ),
            palette: palette
        )
    }

    /// Tokyo Night - github.com/enkia/tokyo-night-vscode-theme
    private static func tokyoNight() -> Theme {
        let palette = ThemePalette(
            background: "#1a1b26",
            foreground: "#a9b1d6",
            cursor: "#c0caf5",
            selectionBackground: "#33467c",
            selectionForeground: "#c0caf5",
            tabActiveBackground: "#1a1b26",
            tabActiveForeground: "#a9b1d6",
            tabInactiveBackground: "#16161e",
            tabInactiveForeground: "#565f89",
            badgeAttention: "#e0af68",
            badgeCompleted: "#9ece6a",
            badgeError: "#f7768e",
            badgeWorking: "#7aa2f7",
            ansiColors: [
                "#414868", "#f7768e", "#9ece6a", "#e0af68",
                "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",
                "#414868", "#f7768e", "#9ece6a", "#e0af68",
                "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"
            ]
        )

        return Theme(
            metadata: ThemeMetadata(
                name: "Tokyo Night",
                variant: .dark,
                author: "Enkia",
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
