// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppLanguageConfigRoundTripTests.swift - TOML round-trip coverage
// for the app-language appearance key.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - app-language TOML round-trip")
struct AppLanguageConfigRoundTripTests {

    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?

        init(content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func loadConfig(from toml: String) throws -> CocxyConfig {
        let provider = InMemoryProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service.current
    }

    @Test
    func defaultConfigUsesSystemLanguage() {
        #expect(CocxyConfig.defaults.appearance.appLanguage == .system)
    }

    @Test
    func defaultTomlTemplateContainsSystemLanguage() {
        let generated = ConfigService.generateDefaultToml()
        #expect(generated.contains("app-language = \"system\""))
    }

    @Test
    func tomlRoundTripPreservesExplicitLanguages() throws {
        let spanish = try loadConfig(from: """
        [appearance]
        app-language = "es"
        """)
        let english = try loadConfig(from: """
        [appearance]
        app-language = "en-US"
        """)
        let french = try loadConfig(from: """
        [appearance]
        app-language = "fr-FR"
        """)
        let portugueseBrazil = try loadConfig(from: """
        [appearance]
        app-language = "pt_BR"
        """)
        let chineseSimplified = try loadConfig(from: """
        [appearance]
        app-language = "zh-Hans"
        """)

        #expect(spanish.appearance.appLanguage == .spanish)
        #expect(english.appearance.appLanguage == .english)
        #expect(french.appearance.appLanguage.rawValue == "fr")
        #expect(portugueseBrazil.appearance.appLanguage.rawValue == "pt-BR")
        #expect(chineseSimplified.appearance.appLanguage.rawValue == "zh-CN")
    }

    @Test
    func missingOrInvalidValueFallsBackToSystem() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let invalid = try loadConfig(from: """
        [appearance]
        app-language = "xx-ZZ"
        """)
        let wrongType = try loadConfig(from: """
        [appearance]
        app-language = true
        """)

        #expect(missing.appearance.appLanguage == .system)
        #expect(invalid.appearance.appLanguage == .system)
        #expect(wrongType.appearance.appLanguage == .system)
    }

    @Test
    func legacyJsonWithoutKeyDecodesAsSystem() throws {
        let json = """
        {
          "theme": "catppuccin-mocha",
          "lightTheme": "catppuccin-latte",
          "fontFamily": "Menlo",
          "fontSize": 14,
          "tabPosition": "left",
          "windowPadding": 8,
          "windowPaddingX": null,
          "windowPaddingY": null,
          "ligatures": false,
          "backgroundOpacity": 1.0,
          "backgroundBlurRadius": 0
        }
        """

        let decoded = try JSONDecoder().decode(AppearanceConfig.self, from: Data(json.utf8))
        #expect(decoded.appLanguage == .system)
    }

    @Test
    func projectOverridesPreserveAppLanguage() {
        let base = CocxyConfig.defaults
        let spanishAppearance = AppearanceConfig(
            theme: base.appearance.theme,
            lightTheme: base.appearance.lightTheme,
            fontFamily: base.appearance.fontFamily,
            fontSize: base.appearance.fontSize,
            tabPosition: base.appearance.tabPosition,
            windowPadding: base.appearance.windowPadding,
            windowPaddingX: base.appearance.windowPaddingX,
            windowPaddingY: base.appearance.windowPaddingY,
            ligatures: base.appearance.ligatures,
            fontThicken: base.appearance.fontThicken,
            backgroundOpacity: base.appearance.backgroundOpacity,
            backgroundBlurRadius: base.appearance.backgroundBlurRadius,
            transparencyChromeTheme: base.appearance.transparencyChromeTheme,
            auroraEnabled: base.appearance.auroraEnabled,
            auroraSidebarDisplayMode: base.appearance.auroraSidebarDisplayMode,
            auroraSidebarPrimaryInfo: base.appearance.auroraSidebarPrimaryInfo,
            rateLimitIndicatorEnabled: base.appearance.rateLimitIndicatorEnabled,
            quickSwitchMode: base.appearance.quickSwitchMode,
            appLanguage: .spanish
        )
        let root = CocxyConfig(
            general: base.general,
            appearance: spanishAppearance,
            terminal: base.terminal,
            agentDetection: base.agentDetection,
            codeReview: base.codeReview,
            notifications: base.notifications,
            quickTerminal: base.quickTerminal,
            keybindings: base.keybindings,
            sessions: base.sessions
        )

        let merged = root.applying(projectOverrides: ProjectConfig(fontSize: 18))

        #expect(merged.appearance.appLanguage == .spanish)
        #expect(merged.appearance.fontSize == 18)
    }
}
