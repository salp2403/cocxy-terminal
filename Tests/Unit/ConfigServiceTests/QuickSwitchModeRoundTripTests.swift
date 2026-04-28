// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickSwitchModeRoundTripTests.swift - TOML round-trip coverage
// for the quickswitch-mode appearance key.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService — quickswitch-mode TOML round-trip")
struct QuickSwitchModeRoundTripTests {

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
    func defaultConfigUsesUnifiedMode() {
        #expect(CocxyConfig.defaults.appearance.quickSwitchMode == .unified)
    }

    @Test
    func defaultTomlTemplateContainsUnifiedMode() {
        let generated = ConfigService.generateDefaultToml()
        #expect(generated.contains("quickswitch-mode = \"unified\""))
    }

    @Test
    func tomlRoundTripPreservesUnifiedMode() throws {
        let config = try loadConfig(from: """
        [appearance]
        quickswitch-mode = "unified"
        """)

        #expect(config.appearance.quickSwitchMode == .unified)
    }

    @Test
    func tomlRoundTripPreservesTabsOnlyMode() throws {
        let config = try loadConfig(from: """
        [appearance]
        quickswitch-mode = "tabs-only"
        """)

        #expect(config.appearance.quickSwitchMode == .tabsOnly)
    }

    @Test
    func missingKeyFallsBackToUnifiedMode() throws {
        let config = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)

        #expect(config.appearance.quickSwitchMode == .unified)
    }

    @Test
    func invalidStringFallsBackToUnifiedMode() throws {
        let config = try loadConfig(from: """
        [appearance]
        quickswitch-mode = "classic"
        """)

        #expect(config.appearance.quickSwitchMode == .unified)
    }

    @Test
    func invalidTypeFallsBackToUnifiedMode() throws {
        let config = try loadConfig(from: """
        [appearance]
        quickswitch-mode = true
        """)

        #expect(config.appearance.quickSwitchMode == .unified)
    }

    @Test
    func generatedTomlWithTabsOnlyPreservesValue() throws {
        let base = ConfigService.generateDefaultToml()
        let toggled = base.replacingOccurrences(
            of: "quickswitch-mode = \"unified\"",
            with: "quickswitch-mode = \"tabs-only\""
        )
        let config = try loadConfig(from: toggled)

        #expect(config.appearance.quickSwitchMode == .tabsOnly)
    }

    @Test
    func legacyJsonWithoutKeyDecodesAsUnifiedMode() throws {
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
        #expect(decoded.quickSwitchMode == .unified)
    }

    @Test
    func projectOverridesPreserveQuickSwitchMode() {
        let base = CocxyConfig.defaults
        let tabsOnlyAppearance = AppearanceConfig(
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
            rateLimitIndicatorEnabled: base.appearance.rateLimitIndicatorEnabled,
            quickSwitchMode: .tabsOnly
        )
        let root = CocxyConfig(
            general: base.general,
            appearance: tabsOnlyAppearance,
            terminal: base.terminal,
            agentDetection: base.agentDetection,
            codeReview: base.codeReview,
            notifications: base.notifications,
            quickTerminal: base.quickTerminal,
            keybindings: base.keybindings,
            sessions: base.sessions
        )

        let merged = root.applying(projectOverrides: ProjectConfig(fontSize: 18))

        #expect(merged.appearance.quickSwitchMode == .tabsOnly)
        #expect(merged.appearance.fontSize == 18)
    }
}
