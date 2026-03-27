// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BuiltInThemeColorTests.swift - Snapshot tests verifying built-in theme colors
// match their official specifications.

import XCTest
@testable import CocxyTerminal

// MARK: - Catppuccin Mocha Official Colors Tests

/// Verifies that the Catppuccin Mocha built-in theme matches the official
/// specification from https://github.com/catppuccin/catppuccin.
///
/// Each test checks a specific color value against the published hex value.
/// These are snapshot tests: if anyone changes a color, the test fails.
@MainActor
final class CatppuccinMochaOfficialColorsTests: XCTestCase {

    private var palette: ThemePalette!

    override func setUp() {
        super.setUp()
        let engine = ThemeEngineImpl()
        palette = (try? engine.themeByName("Catppuccin Mocha"))?.palette
        XCTAssertNotNil(palette, "Catppuccin Mocha must exist as a built-in theme")
    }

    func testMochaBackgroundIsBase() {
        // Base: #1e1e2e
        XCTAssertEqual(palette.background, "#1e1e2e")
    }

    func testMochaForegroundIsText() {
        // Text: #cdd6f4
        XCTAssertEqual(palette.foreground, "#cdd6f4")
    }

    func testMochaAnsiBlackIsSurface0() {
        // Surface0: #45475a (ANSI black = index 0)
        XCTAssertEqual(palette.ansiColors[0], "#45475a")
    }

    func testMochaAnsiRedIsRed() {
        // Red: #f38ba8
        XCTAssertEqual(palette.ansiColors[1], "#f38ba8")
    }

    func testMochaAnsiGreenIsGreen() {
        // Green: #a6e3a1
        XCTAssertEqual(palette.ansiColors[2], "#a6e3a1")
    }

    func testMochaAnsiYellowIsYellow() {
        // Yellow: #f9e2af
        XCTAssertEqual(palette.ansiColors[3], "#f9e2af")
    }

    func testMochaAnsiBlueIsBlue() {
        // Blue: #89b4fa
        XCTAssertEqual(palette.ansiColors[4], "#89b4fa")
    }

    func testMochaAnsiMagentaIsPink() {
        // Pink: #f5c2e7
        XCTAssertEqual(palette.ansiColors[5], "#f5c2e7")
    }

    func testMochaAnsiCyanIsTeal() {
        // Teal: #94e2d5
        XCTAssertEqual(palette.ansiColors[6], "#94e2d5")
    }

    func testMochaBrightBlackIsSurface1() {
        // Surface1: #585b70 (ANSI bright black = index 8)
        XCTAssertEqual(palette.ansiColors[8], "#585b70")
    }

    func testMochaBrightWhiteIsSubtext0() {
        // Subtext0: #a6adc8 (ANSI bright white = index 15)
        XCTAssertEqual(palette.ansiColors[15], "#a6adc8")
    }

    func testMochaTabInactiveBackgroundIsMantle() {
        // Mantle: #181825
        XCTAssertEqual(palette.tabInactiveBackground, "#181825")
    }

    func testMochaTabInactiveForegroundIsOverlay0() {
        // Overlay0: #6c7086
        XCTAssertEqual(palette.tabInactiveForeground, "#6c7086")
    }

    func testMochaSelectionBackgroundIsSurface2() {
        // Surface2: #585b70
        XCTAssertEqual(palette.selectionBackground, "#585b70")
    }
}

// MARK: - Catppuccin Latte Official Colors Tests

/// Verifies that the Catppuccin Latte built-in theme matches the official
/// specification from https://github.com/catppuccin/catppuccin.
@MainActor
final class CatppuccinLatteOfficialColorsTests: XCTestCase {

    private var palette: ThemePalette!

    override func setUp() {
        super.setUp()
        let engine = ThemeEngineImpl()
        palette = (try? engine.themeByName("Catppuccin Latte"))?.palette
        XCTAssertNotNil(palette, "Catppuccin Latte must exist as a built-in theme")
    }

    func testLatteBackgroundIsBase() {
        // Base: #eff1f5
        XCTAssertEqual(palette.background, "#eff1f5")
    }

    func testLatteForegroundIsText() {
        // Text: #4c4f69
        XCTAssertEqual(palette.foreground, "#4c4f69")
    }

    func testLatteAnsiRedIsRed() {
        // Red: #d20f39
        XCTAssertEqual(palette.ansiColors[1], "#d20f39")
    }

    func testLatteAnsiGreenIsGreen() {
        // Green: #40a02b
        XCTAssertEqual(palette.ansiColors[2], "#40a02b")
    }

    func testLatteAnsiYellowIsYellow() {
        // Yellow: #df8e1d
        XCTAssertEqual(palette.ansiColors[3], "#df8e1d")
    }

    func testLatteAnsiBlueIsBlue() {
        // Blue: #1e66f5
        XCTAssertEqual(palette.ansiColors[4], "#1e66f5")
    }

    func testLatteAnsiMagentaIsPink() {
        // Pink: #ea76cb
        XCTAssertEqual(palette.ansiColors[5], "#ea76cb")
    }

    func testLatteAnsiCyanIsTeal() {
        // Teal: #179299
        XCTAssertEqual(palette.ansiColors[6], "#179299")
    }

    func testLatteTabInactiveBackgroundIsMantle() {
        // Mantle: #e6e9ef
        XCTAssertEqual(palette.tabInactiveBackground, "#e6e9ef")
    }

    func testLatteSelectionBackgroundIsSurface2() {
        // Surface2: #acb0be
        XCTAssertEqual(palette.selectionBackground, "#acb0be")
    }
}

// MARK: - One Dark Official Colors Tests

/// Verifies that the One Dark built-in theme matches the Atom One Dark palette.
@MainActor
final class OneDarkOfficialColorsTests: XCTestCase {

    private var palette: ThemePalette!

    override func setUp() {
        super.setUp()
        let engine = ThemeEngineImpl()
        palette = (try? engine.themeByName("One Dark"))?.palette
        XCTAssertNotNil(palette, "One Dark must exist as a built-in theme")
    }

    func testOneDarkBackground() {
        XCTAssertEqual(palette.background, "#282c34")
    }

    func testOneDarkForeground() {
        XCTAssertEqual(palette.foreground, "#abb2bf")
    }

    func testOneDarkAnsiRed() {
        XCTAssertEqual(palette.ansiColors[1], "#e06c75")
    }

    func testOneDarkAnsiGreen() {
        XCTAssertEqual(palette.ansiColors[2], "#98c379")
    }
}

// MARK: - Solarized Dark Official Colors Tests

/// Verifies that the Solarized Dark built-in theme matches the official
/// Solarized palette from ethanschoonover.com.
@MainActor
final class SolarizedDarkOfficialColorsTests: XCTestCase {

    private var palette: ThemePalette!

    override func setUp() {
        super.setUp()
        let engine = ThemeEngineImpl()
        palette = (try? engine.themeByName("Solarized Dark"))?.palette
        XCTAssertNotNil(palette, "Solarized Dark must exist as a built-in theme")
    }

    func testSolarizedDarkBackground() {
        // base03: #002b36
        XCTAssertEqual(palette.background, "#002b36")
    }

    func testSolarizedDarkForeground() {
        // base0: #839496
        XCTAssertEqual(palette.foreground, "#839496")
    }

    func testSolarizedDarkAnsiRed() {
        XCTAssertEqual(palette.ansiColors[1], "#dc322f")
    }

    func testSolarizedDarkAnsiBlue() {
        XCTAssertEqual(palette.ansiColors[4], "#268bd2")
    }
}

// MARK: - Solarized Light Official Colors Tests

/// Verifies that the Solarized Light built-in theme matches the official
/// Solarized palette.
@MainActor
final class SolarizedLightOfficialColorsTests: XCTestCase {

    private var palette: ThemePalette!

    override func setUp() {
        super.setUp()
        let engine = ThemeEngineImpl()
        palette = (try? engine.themeByName("Solarized Light"))?.palette
        XCTAssertNotNil(palette, "Solarized Light must exist as a built-in theme")
    }

    func testSolarizedLightBackground() {
        // base3: #fdf6e3
        XCTAssertEqual(palette.background, "#fdf6e3")
    }

    func testSolarizedLightForeground() {
        // base00: #657b83
        XCTAssertEqual(palette.foreground, "#657b83")
    }
}

// MARK: - TOML Theme Loading Tests

/// Tests that themes can be loaded from TOML format and produce correct palettes.
@MainActor
final class ThemeTomlLoadingTests: XCTestCase {

    func testCatppuccinMochaTomlProducesCorrectPalette() throws {
        let toml = CatppuccinMochaTomlFixture.content

        let theme = try ThemeTomlParser.parse(toml)

        XCTAssertEqual(theme.metadata.name, "Catppuccin Mocha")
        XCTAssertEqual(theme.metadata.variant, .dark)
        XCTAssertEqual(theme.palette.background, "#1e1e2e")
        XCTAssertEqual(theme.palette.foreground, "#cdd6f4")
        XCTAssertEqual(theme.palette.ansiColors[1], "#f38ba8")
        XCTAssertEqual(theme.palette.ansiColors[4], "#89b4fa")
    }

    func testCatppuccinLatteTomlProducesCorrectPalette() throws {
        let toml = CatppuccinLatteTomlFixture.content

        let theme = try ThemeTomlParser.parse(toml)

        XCTAssertEqual(theme.metadata.name, "Catppuccin Latte")
        XCTAssertEqual(theme.metadata.variant, .light)
        XCTAssertEqual(theme.palette.background, "#eff1f5")
        XCTAssertEqual(theme.palette.foreground, "#4c4f69")
        XCTAssertEqual(theme.palette.ansiColors[1], "#d20f39")
        XCTAssertEqual(theme.palette.ansiColors[6], "#179299")
    }

    func testOneDarkTomlProducesCorrectPalette() throws {
        let toml = OneDarkTomlFixture.content

        let theme = try ThemeTomlParser.parse(toml)

        XCTAssertEqual(theme.metadata.name, "One Dark")
        XCTAssertEqual(theme.palette.background, "#282c34")
        XCTAssertEqual(theme.palette.foreground, "#abb2bf")
    }

    func testSolarizedDarkTomlProducesCorrectPalette() throws {
        let toml = SolarizedDarkTomlFixture.content

        let theme = try ThemeTomlParser.parse(toml)

        XCTAssertEqual(theme.metadata.name, "Solarized Dark")
        XCTAssertEqual(theme.palette.background, "#002b36")
        XCTAssertEqual(theme.palette.ansiColors[1], "#dc322f")
    }

    func testSolarizedLightTomlProducesCorrectPalette() throws {
        let toml = SolarizedLightTomlFixture.content

        let theme = try ThemeTomlParser.parse(toml)

        XCTAssertEqual(theme.metadata.name, "Solarized Light")
        XCTAssertEqual(theme.palette.background, "#fdf6e3")
    }
}

// MARK: - TOML Fixture Data

/// Catppuccin Mocha TOML fixture with official colors.
enum CatppuccinMochaTomlFixture {
    static let content = """
    [metadata]
    name = "Catppuccin Mocha"
    author = "Catppuccin"
    variant = "dark"

    [colors]
    foreground = "#cdd6f4"
    background = "#1e1e2e"
    cursor = "#f5e0dc"
    selection = "#585b70"

    [colors.normal]
    black = "#45475a"
    red = "#f38ba8"
    green = "#a6e3a1"
    yellow = "#f9e2af"
    blue = "#89b4fa"
    magenta = "#f5c2e7"
    cyan = "#94e2d5"
    white = "#bac2de"

    [colors.bright]
    black = "#585b70"
    red = "#f38ba8"
    green = "#a6e3a1"
    yellow = "#f9e2af"
    blue = "#89b4fa"
    magenta = "#f5c2e7"
    cyan = "#94e2d5"
    white = "#a6adc8"

    [ui]
    tab-active-background = "#1e1e2e"
    tab-inactive-background = "#181825"
    tab-inactive-foreground = "#6c7086"
    badge-attention = "#f9e2af"
    badge-completed = "#a6e3a1"
    badge-error = "#f38ba8"
    badge-working = "#89b4fa"
    """
}

/// Catppuccin Latte TOML fixture with official colors.
enum CatppuccinLatteTomlFixture {
    static let content = """
    [metadata]
    name = "Catppuccin Latte"
    author = "Catppuccin"
    variant = "light"

    [colors]
    foreground = "#4c4f69"
    background = "#eff1f5"
    cursor = "#dc8a78"
    selection = "#acb0be"

    [colors.normal]
    black = "#5c5f77"
    red = "#d20f39"
    green = "#40a02b"
    yellow = "#df8e1d"
    blue = "#1e66f5"
    magenta = "#ea76cb"
    cyan = "#179299"
    white = "#acb0be"

    [colors.bright]
    black = "#6c6f85"
    red = "#d20f39"
    green = "#40a02b"
    yellow = "#df8e1d"
    blue = "#1e66f5"
    magenta = "#ea76cb"
    cyan = "#179299"
    white = "#bcc0cc"

    [ui]
    tab-active-background = "#eff1f5"
    tab-inactive-background = "#e6e9ef"
    tab-inactive-foreground = "#9ca0b0"
    badge-attention = "#df8e1d"
    badge-completed = "#40a02b"
    badge-error = "#d20f39"
    badge-working = "#1e66f5"
    """
}

/// One Dark TOML fixture.
enum OneDarkTomlFixture {
    static let content = """
    [metadata]
    name = "One Dark"
    author = "Atom"
    variant = "dark"

    [colors]
    foreground = "#abb2bf"
    background = "#282c34"
    cursor = "#528bff"
    selection = "#3e4451"

    [colors.normal]
    black = "#282c34"
    red = "#e06c75"
    green = "#98c379"
    yellow = "#e5c07b"
    blue = "#61afef"
    magenta = "#c678dd"
    cyan = "#56b6c2"
    white = "#abb2bf"

    [colors.bright]
    black = "#545862"
    red = "#e06c75"
    green = "#98c379"
    yellow = "#e5c07b"
    blue = "#61afef"
    magenta = "#c678dd"
    cyan = "#56b6c2"
    white = "#c8ccd4"
    """
}

/// Solarized Dark TOML fixture.
enum SolarizedDarkTomlFixture {
    static let content = """
    [metadata]
    name = "Solarized Dark"
    author = "Ethan Schoonover"
    variant = "dark"

    [colors]
    foreground = "#839496"
    background = "#002b36"
    cursor = "#93a1a1"
    selection = "#073642"

    [colors.normal]
    black = "#073642"
    red = "#dc322f"
    green = "#859900"
    yellow = "#b58900"
    blue = "#268bd2"
    magenta = "#d33682"
    cyan = "#2aa198"
    white = "#eee8d5"

    [colors.bright]
    black = "#002b36"
    red = "#cb4b16"
    green = "#586e75"
    yellow = "#657b83"
    blue = "#839496"
    magenta = "#6c71c4"
    cyan = "#93a1a1"
    white = "#fdf6e3"
    """
}

/// Solarized Light TOML fixture.
enum SolarizedLightTomlFixture {
    static let content = """
    [metadata]
    name = "Solarized Light"
    author = "Ethan Schoonover"
    variant = "light"

    [colors]
    foreground = "#657b83"
    background = "#fdf6e3"
    cursor = "#586e75"
    selection = "#eee8d5"

    [colors.normal]
    black = "#073642"
    red = "#dc322f"
    green = "#859900"
    yellow = "#b58900"
    blue = "#268bd2"
    magenta = "#d33682"
    cyan = "#2aa198"
    white = "#eee8d5"

    [colors.bright]
    black = "#002b36"
    red = "#cb4b16"
    green = "#586e75"
    yellow = "#657b83"
    blue = "#839496"
    magenta = "#6c71c4"
    cyan = "#93a1a1"
    white = "#fdf6e3"
    """
}
