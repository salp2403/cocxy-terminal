// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraThemeToggleSwiftTestingTests.swift - Light/dark toolbar toggle target tests.

import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Aurora theme toggle")
struct AuroraThemeToggleSwiftTestingTests {
    @Test("light mode toggles back to default dark theme when configured dark theme follows system")
    func lightModeFallsBackToDefaultDarkThemeForSystemSentinel() {
        let engine = ThemeEngineImpl()
        let appearance = AppearanceConfig(
            theme: "system",
            lightTheme: "catppuccin-latte",
            fontFamily: "Menlo",
            fontSize: 14,
            tabPosition: .left,
            windowPadding: 8,
            windowPaddingX: nil,
            windowPaddingY: nil,
            ligatures: false,
            backgroundOpacity: 1,
            backgroundBlurRadius: 0
        )

        let target = MainWindowController.auroraThemeToggleTargetName(
            currentVariant: .light,
            appearance: appearance,
            themeEngine: engine
        )

        #expect(target == "Catppuccin Mocha")
    }

    @Test("light mode refuses a configured light theme as the dark target")
    func lightModeRejectsWrongVariantDarkTarget() {
        let engine = ThemeEngineImpl()
        let appearance = AppearanceConfig(
            theme: "catppuccin-latte",
            lightTheme: "solarized-light",
            fontFamily: "Menlo",
            fontSize: 14,
            tabPosition: .left,
            windowPadding: 8,
            windowPaddingX: nil,
            windowPaddingY: nil,
            ligatures: false,
            backgroundOpacity: 1,
            backgroundBlurRadius: 0
        )

        let target = MainWindowController.auroraThemeToggleTargetName(
            currentVariant: .light,
            appearance: appearance,
            themeEngine: engine
        )

        #expect(target == "Catppuccin Mocha")
    }

    @Test("dark mode toggles to configured light theme")
    func darkModeUsesConfiguredLightTheme() {
        let engine = ThemeEngineImpl()
        let appearance = AppearanceConfig(
            theme: "catppuccin-mocha",
            lightTheme: "solarized-light",
            fontFamily: "Menlo",
            fontSize: 14,
            tabPosition: .left,
            windowPadding: 8,
            windowPaddingX: nil,
            windowPaddingY: nil,
            ligatures: false,
            backgroundOpacity: 1,
            backgroundBlurRadius: 0
        )

        let target = MainWindowController.auroraThemeToggleTargetName(
            currentVariant: .dark,
            appearance: appearance,
            themeEngine: engine
        )

        #expect(target == "Solarized Light")
    }
}

