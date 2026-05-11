// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemeSelectionResolverSwiftTestingTests.swift - Concrete theme resolution coverage.

import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Theme selection resolver")
struct ThemeSelectionResolverSwiftTestingTests {
    @Test("system alias resolves to default dark theme when system is dark")
    func systemAliasResolvesToDefaultDarkTheme() {
        let engine = ThemeEngineImpl()

        let resolved = ThemeSelectionResolver.resolvedConfiguredThemeName(
            "system",
            isSystemDarkMode: true,
            themeEngine: engine
        )

        #expect(resolved == "Catppuccin Mocha")
    }

    @Test("system alias resolves to default light theme when system is light")
    func systemAliasResolvesToDefaultLightTheme() {
        let engine = ThemeEngineImpl()

        let resolved = ThemeSelectionResolver.resolvedConfiguredThemeName(
            "follow-system",
            isSystemDarkMode: false,
            themeEngine: engine
        )

        #expect(resolved == "Catppuccin Latte")
    }

    @Test("configured concrete theme resolves through theme engine aliases")
    func concreteThemeResolvesNormalizedName() {
        let engine = ThemeEngineImpl()

        let resolved = ThemeSelectionResolver.resolvedConfiguredThemeName(
            "catppuccin-latte",
            isSystemDarkMode: true,
            themeEngine: engine
        )

        #expect(resolved == "Catppuccin Latte")
    }

    @Test("variant resolver rejects preferred theme with wrong variant")
    func variantResolverRejectsWrongVariantPreferredTheme() {
        let engine = ThemeEngineImpl()

        let resolved = ThemeSelectionResolver.resolvedVariantThemeName(
            preferredName: "catppuccin-latte",
            fallbackName: "catppuccin-mocha",
            requiredVariant: .dark,
            themeEngine: engine
        )

        #expect(resolved == "Catppuccin Mocha")
    }
}
