// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemeEngineTests.swift - Tests for ThemeEngine theme loading and application.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Theme Engine Tests

/// Tests for `ThemeEngineImpl` covering theme loading, selection and publishing.
///
/// Uses `InMemoryThemeFileProvider` to avoid filesystem dependency.
/// All test classes are `@MainActor` because `ThemeProviding` is `@MainActor`.
///
/// Covers:
/// - Built-in theme loading
/// - Theme selection by name
/// - Unknown theme selection (no change)
/// - Theme changed publisher
/// - Custom theme loading from TOML
/// - Invalid theme file handling (skip without crash)
/// - Theme TOML parsing
/// - Available themes list
///
/// - SeeAlso: ADR-007 (Theme system)

// MARK: - In-Memory Theme File Provider

/// Test double that provides theme TOML content from memory.
///
/// Simulates both built-in and custom theme directories without filesystem access.
final class InMemoryThemeFileProvider: ThemeFileProviding {
    var customThemeFiles: [String: String]

    init(customThemeFiles: [String: String] = [:]) {
        self.customThemeFiles = customThemeFiles
    }

    func listCustomThemeFiles() -> [(name: String, content: String)] {
        customThemeFiles.map { (name: $0.key, content: $0.value) }
    }
}

// MARK: - Built-In Theme Tests

@MainActor
final class ThemeEngineBuiltInTests: XCTestCase {

    func testBuiltInThemesAreAvailable() {
        let engine = ThemeEngineImpl()

        XCTAssertFalse(
            engine.availableThemes.isEmpty,
            "ThemeEngine must provide at least one built-in theme"
        )
    }

    func testBuiltInThemesContainCatppuccinMocha() {
        let engine = ThemeEngineImpl()

        let hasCatppuccin = engine.availableThemes.contains { $0.name == "Catppuccin Mocha" }
        XCTAssertTrue(hasCatppuccin, "Built-in themes must include Catppuccin Mocha")
    }

    func testBuiltInThemesContainCatppuccinLatte() {
        let engine = ThemeEngineImpl()

        let hasLatte = engine.availableThemes.contains { $0.name == "Catppuccin Latte" }
        XCTAssertTrue(hasLatte, "Built-in themes must include Catppuccin Latte")
    }

    func testBuiltInThemesContainOneDark() {
        let engine = ThemeEngineImpl()

        let hasOneDark = engine.availableThemes.contains { $0.name == "One Dark" }
        XCTAssertTrue(hasOneDark, "Built-in themes must include One Dark")
    }

    func testBuiltInThemesContainDracula() {
        let engine = ThemeEngineImpl()

        let hasDracula = engine.availableThemes.contains { $0.name == "Dracula" }
        XCTAssertTrue(hasDracula, "Built-in themes must include Dracula")
    }

    func testBuiltInThemesContainSolarizedDark() {
        let engine = ThemeEngineImpl()

        let hasSolarized = engine.availableThemes.contains { $0.name == "Solarized Dark" }
        XCTAssertTrue(hasSolarized, "Built-in themes must include Solarized Dark")
    }

    func testBuiltInThemesContainSolarizedLight() {
        let engine = ThemeEngineImpl()

        let hasSolarized = engine.availableThemes.contains { $0.name == "Solarized Light" }
        XCTAssertTrue(hasSolarized, "Built-in themes must include Solarized Light")
    }

    func testBuiltInThemesHaveSixEntries() {
        let engine = ThemeEngineImpl()

        // ADR-007: 6 built-in themes
        XCTAssertGreaterThanOrEqual(engine.availableThemes.count, 6)
    }

    func testBuiltInThemesHaveCorrectVariants() {
        let engine = ThemeEngineImpl()

        let darkThemes = engine.availableThemes.filter { $0.variant == .dark }
        let lightThemes = engine.availableThemes.filter { $0.variant == .light }

        // ADR-007: 4 dark, 2 light built-in
        XCTAssertGreaterThanOrEqual(darkThemes.count, 4)
        XCTAssertGreaterThanOrEqual(lightThemes.count, 2)
    }

    func testBuiltInThemesHaveBuiltInSource() {
        let engine = ThemeEngineImpl()

        let builtInCount = engine.availableThemes.filter {
            if case .builtIn = $0.source { return true }
            return false
        }.count
        XCTAssertGreaterThanOrEqual(builtInCount, 6)
    }
}

// MARK: - Theme Selection Tests

@MainActor
final class ThemeEngineSelectionTests: XCTestCase {

    func testDefaultActiveThemeIsCatppuccinMocha() {
        let engine = ThemeEngineImpl()

        XCTAssertEqual(engine.activeTheme.metadata.name, "Catppuccin Mocha")
    }

    func testApplyThemeByNameChangesActiveTheme() throws {
        let engine = ThemeEngineImpl()

        try engine.apply(themeName: "Dracula")

        XCTAssertEqual(engine.activeTheme.metadata.name, "Dracula")
    }

    func testApplyUnknownThemeThrowsError() {
        let engine = ThemeEngineImpl()

        XCTAssertThrowsError(try engine.apply(themeName: "NonExistentTheme")) { error in
            guard case ThemeError.themeNotFound(let name) = error else {
                XCTFail("Expected themeNotFound error, got \(error)")
                return
            }
            XCTAssertEqual(name, "NonExistentTheme")
        }
    }

    func testApplyThemePreservesActiveThemeOnError() {
        let engine = ThemeEngineImpl()
        let originalThemeName = engine.activeTheme.metadata.name

        _ = try? engine.apply(themeName: "NonExistentTheme")

        XCTAssertEqual(
            engine.activeTheme.metadata.name,
            originalThemeName,
            "Active theme must not change when apply fails"
        )
    }

    func testApplyThemeUpdatesActiveThemePalette() throws {
        let engine = ThemeEngineImpl()

        try engine.apply(themeName: "Dracula")

        XCTAssertEqual(engine.activeTheme.palette.background, "#282a36")
    }
}

// MARK: - Theme Palette Validation Tests

@MainActor
final class ThemePaletteValidationTests: XCTestCase {

    func testBuiltInThemePalettesHaveValidHexColors() {
        let engine = ThemeEngineImpl()

        for themeMetadata in engine.availableThemes {
            if let theme = try? engine.themeByName(themeMetadata.name) {
                assertValidHex(theme.palette.background, context: "\(themeMetadata.name).background")
                assertValidHex(theme.palette.foreground, context: "\(themeMetadata.name).foreground")
                assertValidHex(theme.palette.cursor, context: "\(themeMetadata.name).cursor")
                assertValidHex(theme.palette.selectionBackground, context: "\(themeMetadata.name).selectionBackground")

                XCTAssertEqual(
                    theme.palette.ansiColors.count,
                    16,
                    "\(themeMetadata.name) must have exactly 16 ANSI colors"
                )

                for (index, ansiColor) in theme.palette.ansiColors.enumerated() {
                    assertValidHex(ansiColor, context: "\(themeMetadata.name).ansiColors[\(index)]")
                }
            }
        }
    }

    private func assertValidHex(_ hex: String, context: String) {
        let hexPattern = #"^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$"#
        let regex = try? NSRegularExpression(pattern: hexPattern)
        let range = NSRange(hex.startIndex..<hex.endIndex, in: hex)
        let matchCount = regex?.numberOfMatches(in: hex, range: range) ?? 0
        XCTAssertGreaterThan(matchCount, 0, "Invalid hex color '\(hex)' in \(context)")
    }
}

// MARK: - Theme Changed Publisher Tests

@MainActor
final class ThemeEnginePublisherTests: XCTestCase {

    func testThemeChangedPublisherEmitsOnApply() throws {
        let engine = ThemeEngineImpl()

        let expectation = expectation(description: "Theme change published")
        var receivedTheme: Theme?
        var cancellables = Set<AnyCancellable>()

        engine.themeChangedPublisher
            .dropFirst()
            .sink { theme in
                receivedTheme = theme
                expectation.fulfill()
            }
            .store(in: &cancellables)

        try engine.apply(themeName: "Dracula")

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedTheme?.metadata.name, "Dracula")
    }

    func testThemeChangedPublisherDoesNotEmitOnFailedApply() {
        let engine = ThemeEngineImpl()

        let expectation = expectation(description: "No emission expected")
        expectation.isInverted = true
        var cancellables = Set<AnyCancellable>()

        engine.themeChangedPublisher
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        _ = try? engine.apply(themeName: "NonExistentTheme")

        wait(for: [expectation], timeout: 0.5)
    }
}

// MARK: - Custom Theme Loading Tests

@MainActor
final class ThemeEngineCustomThemeTests: XCTestCase {

    func testLoadCustomThemeFromValidToml() {
        let themeToml = """
        [metadata]
        name = "My Custom Theme"
        author = "Test Author"
        variant = "dark"

        [colors]
        foreground = "#ffffff"
        background = "#000000"
        cursor = "#ff0000"
        selection = "#333333"

        [colors.normal]
        black = "#000000"
        red = "#ff0000"
        green = "#00ff00"
        yellow = "#ffff00"
        blue = "#0000ff"
        magenta = "#ff00ff"
        cyan = "#00ffff"
        white = "#ffffff"

        [colors.bright]
        black = "#666666"
        red = "#ff6666"
        green = "#66ff66"
        yellow = "#ffff66"
        blue = "#6666ff"
        magenta = "#ff66ff"
        cyan = "#66ffff"
        white = "#ffffff"

        [ui]
        tab-bar-background = "#111111"
        tab-active-background = "#222222"
        tab-inactive-background = "#111111"
        split-divider = "#333333"
        status-bar-background = "#111111"
        accent-color = "#0000ff"
        """

        let provider = InMemoryThemeFileProvider(customThemeFiles: [
            "my-custom-theme.toml": themeToml
        ])
        let engine = ThemeEngineImpl(themeFileProvider: provider)

        let hasCustom = engine.availableThemes.contains { $0.name == "My Custom Theme" }
        XCTAssertTrue(hasCustom, "Custom theme must appear in available themes")
    }

    func testCustomThemeHasCorrectMetadata() {
        let themeToml = """
        [metadata]
        name = "Test Theme"
        author = "Test Author"
        variant = "light"

        [colors]
        foreground = "#000000"
        background = "#ffffff"
        cursor = "#000000"
        selection = "#cccccc"

        [colors.normal]
        black = "#000000"
        red = "#ff0000"
        green = "#00ff00"
        yellow = "#ffff00"
        blue = "#0000ff"
        magenta = "#ff00ff"
        cyan = "#00ffff"
        white = "#ffffff"

        [colors.bright]
        black = "#666666"
        red = "#ff6666"
        green = "#66ff66"
        yellow = "#ffff66"
        blue = "#6666ff"
        magenta = "#ff66ff"
        cyan = "#66ffff"
        white = "#ffffff"

        [ui]
        tab-bar-background = "#eeeeee"
        tab-active-background = "#ffffff"
        tab-inactive-background = "#eeeeee"
        split-divider = "#cccccc"
        status-bar-background = "#eeeeee"
        accent-color = "#0000ff"
        """

        let provider = InMemoryThemeFileProvider(customThemeFiles: [
            "test-theme.toml": themeToml
        ])
        let engine = ThemeEngineImpl(themeFileProvider: provider)

        let metadata = engine.availableThemes.first { $0.name == "Test Theme" }
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.variant, .light)
        XCTAssertEqual(metadata?.author, "Test Author")
    }

    func testInvalidThemeFileIsSkippedWithoutCrash() {
        let invalidToml = "this is not valid toml at all!!!"

        let provider = InMemoryThemeFileProvider(customThemeFiles: [
            "broken-theme.toml": invalidToml
        ])
        let engine = ThemeEngineImpl(themeFileProvider: provider)

        XCTAssertGreaterThanOrEqual(engine.availableThemes.count, 6)
    }

    func testThemeWithMissingColorsIsSkipped() {
        let incompleteToml = """
        [metadata]
        name = "Incomplete Theme"
        variant = "dark"

        [colors]
        foreground = "#ffffff"
        """

        let provider = InMemoryThemeFileProvider(customThemeFiles: [
            "incomplete.toml": incompleteToml
        ])
        let engine = ThemeEngineImpl(themeFileProvider: provider)

        let hasIncomplete = engine.availableThemes.contains { $0.name == "Incomplete Theme" }
        XCTAssertFalse(hasIncomplete, "Theme with missing required colors must be skipped")
    }

    func testCustomThemeCanBeApplied() throws {
        let themeToml = """
        [metadata]
        name = "Applicable Theme"
        author = "Tester"
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
        tab-bar-background = "#181825"
        tab-active-background = "#1e1e2e"
        tab-inactive-background = "#181825"
        split-divider = "#313244"
        status-bar-background = "#181825"
        accent-color = "#89b4fa"
        """

        let provider = InMemoryThemeFileProvider(customThemeFiles: [
            "applicable.toml": themeToml
        ])
        let engine = ThemeEngineImpl(themeFileProvider: provider)

        try engine.apply(themeName: "Applicable Theme")

        XCTAssertEqual(engine.activeTheme.metadata.name, "Applicable Theme")
        XCTAssertEqual(engine.activeTheme.palette.background, "#1e1e2e")
        XCTAssertEqual(engine.activeTheme.palette.foreground, "#cdd6f4")
    }
}

// MARK: - Theme TOML Parsing Tests

final class ThemeTomlParsingTests: XCTestCase {

    func testParseThemeTomlExtractsAllColors() throws {
        let toml = """
        [metadata]
        name = "Parse Test"
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
        tab-bar-background = "#181825"
        tab-active-background = "#1e1e2e"
        tab-inactive-background = "#181825"
        split-divider = "#313244"
        status-bar-background = "#181825"
        accent-color = "#89b4fa"
        """

        let theme = try ThemeTomlParser.parse(toml)

        XCTAssertEqual(theme.metadata.name, "Parse Test")
        XCTAssertEqual(theme.metadata.variant, .dark)
        XCTAssertEqual(theme.palette.background, "#1e1e2e")
        XCTAssertEqual(theme.palette.foreground, "#cdd6f4")
        XCTAssertEqual(theme.palette.cursor, "#f5e0dc")
        XCTAssertEqual(theme.palette.selectionBackground, "#585b70")
        XCTAssertEqual(theme.palette.ansiColors.count, 16)
        XCTAssertEqual(theme.palette.ansiColors[0], "#45475a")  // black
        XCTAssertEqual(theme.palette.ansiColors[1], "#f38ba8")  // red
        XCTAssertEqual(theme.palette.ansiColors[8], "#585b70")  // bright black
        XCTAssertEqual(theme.palette.tabActiveBackground, "#1e1e2e")
    }

    func testParseThemeTomlWithOptionalUIColorsDerivesDefaults() throws {
        let toml = """
        [metadata]
        name = "No UI Theme"
        variant = "dark"

        [colors]
        foreground = "#ffffff"
        background = "#000000"
        cursor = "#ffffff"
        selection = "#333333"

        [colors.normal]
        black = "#000000"
        red = "#ff0000"
        green = "#00ff00"
        yellow = "#ffff00"
        blue = "#0000ff"
        magenta = "#ff00ff"
        cyan = "#00ffff"
        white = "#ffffff"

        [colors.bright]
        black = "#666666"
        red = "#ff6666"
        green = "#66ff66"
        yellow = "#ffff66"
        blue = "#6666ff"
        magenta = "#ff66ff"
        cyan = "#66ffff"
        white = "#ffffff"
        """

        let theme = try ThemeTomlParser.parse(toml)

        // UI colors should be derived from the palette
        XCTAssertFalse(theme.palette.tabActiveBackground.isEmpty)
        XCTAssertFalse(theme.palette.tabInactiveBackground.isEmpty)
        XCTAssertFalse(theme.palette.badgeAttention.isEmpty)
        XCTAssertFalse(theme.palette.badgeCompleted.isEmpty)
        XCTAssertFalse(theme.palette.badgeError.isEmpty)
        XCTAssertFalse(theme.palette.badgeWorking.isEmpty)
    }

    func testParseThemeTomlWithMissingMetadataThrowsError() {
        let toml = """
        [colors]
        foreground = "#ffffff"
        background = "#000000"
        """

        XCTAssertThrowsError(try ThemeTomlParser.parse(toml)) { error in
            guard case ThemeError.parseFailed = error else {
                XCTFail("Expected parseFailed error, got \(error)")
                return
            }
        }
    }

    func testParseThemeTomlWithMissingBackgroundThrowsError() {
        let toml = """
        [metadata]
        name = "No Background"
        variant = "dark"

        [colors]
        foreground = "#ffffff"
        """

        XCTAssertThrowsError(try ThemeTomlParser.parse(toml)) { error in
            guard case ThemeError.parseFailed = error else {
                XCTFail("Expected parseFailed error, got \(error)")
                return
            }
        }
    }
}

// MARK: - Theme By Name Tests

@MainActor
final class ThemeByNameTests: XCTestCase {

    func testThemeByNameReturnsCorrectTheme() throws {
        let engine = ThemeEngineImpl()

        let theme = try engine.themeByName("Catppuccin Mocha")

        XCTAssertEqual(theme.metadata.name, "Catppuccin Mocha")
        XCTAssertEqual(theme.metadata.variant, .dark)
    }

    func testThemeByNameThrowsForUnknownTheme() {
        let engine = ThemeEngineImpl()

        XCTAssertThrowsError(try engine.themeByName("Unknown Theme")) { error in
            guard case ThemeError.themeNotFound = error else {
                XCTFail("Expected themeNotFound error, got \(error)")
                return
            }
        }
    }
}
