// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RateLimitIndicatorRoundTripTests.swift - TOML round-trip coverage
// for the rate-limit-indicator-enabled appearance key.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService — rate-limit-indicator-enabled TOML round-trip")
struct RateLimitIndicatorRoundTripTests {

    // MARK: - Helpers

    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        private(set) var writtenContent: String?

        init(content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }

        func writeConfigFile(_ content: String) throws {
            writtenContent = content
            self.content = content
        }
    }

    private func loadConfig(from toml: String) throws -> CocxyConfig {
        let provider = InMemoryProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service.current
    }

    // MARK: - Defaults

    @Test
    func defaultConfigHasRateLimitIndicatorEnabled() {
        let defaults = CocxyConfig.defaults
        #expect(defaults.appearance.rateLimitIndicatorEnabled == true)
    }

    @Test
    func defaultTomlTemplateContainsRateLimitIndicatorTrue() {
        let generated = ConfigService.generateDefaultToml()
        #expect(generated.contains("rate-limit-indicator-enabled = true"))
    }

    // MARK: - Round-trip

    @Test
    func tomlRoundTripPreservesTrueValue() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        rate-limit-indicator-enabled = true
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.rateLimitIndicatorEnabled == true)
    }

    @Test
    func tomlRoundTripPreservesFalseValue() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        rate-limit-indicator-enabled = false
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.rateLimitIndicatorEnabled == false)
    }

    // MARK: - Tolerant parsing

    @Test
    func missingKeyProducesEnabledDefault() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.rateLimitIndicatorEnabled == true)
    }

    @Test
    func invalidTypeFallsBackToEnabledDefault() throws {
        // Mirrors the tolerant contract used by every other Bool key in
        // ConfigService: a wrong-shaped value falls back to the runtime
        // default rather than crashing the load.
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        rate-limit-indicator-enabled = "yes"
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.rateLimitIndicatorEnabled == true)
    }

    @Test
    func emptyAppearanceSectionProducesEnabledDefault() throws {
        let toml = """
        [appearance]
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.rateLimitIndicatorEnabled == true)
    }

    // MARK: - Generated TOML round-trip

    @Test
    func generatedTomlWithToggleOffPreservesValue() throws {
        // Simulates Preferences writing a toggled config back to disk:
        // start from the default template, flip the flag, then reload.
        let base = ConfigService.generateDefaultToml()
        let toggled = base.replacingOccurrences(
            of: "rate-limit-indicator-enabled = true",
            with: "rate-limit-indicator-enabled = false"
        )
        let config = try loadConfig(from: toggled)
        #expect(config.appearance.rateLimitIndicatorEnabled == false)
    }

    // MARK: - Decoder backwards compatibility

    @Test
    func legacyJsonWithoutKeyDecodesAsEnabledDefault() throws {
        // Simulates a CocxyConfig persisted before this key existed:
        // the decoder must treat the missing key as the runtime default
        // (true) so older session JSON snapshots round-trip cleanly.
        let legacyJson = """
        {
          "general": {
            "shell": "/bin/zsh",
            "workingDirectory": "~",
            "confirmCloseProcess": true
          },
          "appearance": {
            "theme": "catppuccin-mocha",
            "lightTheme": "catppuccin-latte",
            "fontFamily": "Menlo",
            "fontSize": 14,
            "tabPosition": "left",
            "windowPadding": 8,
            "windowPaddingX": null,
            "windowPaddingY": null,
            "ligatures": false,
            "backgroundOpacity": 0.9,
            "backgroundBlurRadius": 0
          },
          "terminal": {
            "scrollbackLines": 10000,
            "cursorStyle": "bar",
            "cursorBlink": true,
            "cursorOpacity": 0.8,
            "mouseHideWhileTyping": true,
            "copyOnSelect": true,
            "clipboardPasteProtection": true,
            "clipboardReadAccess": "prompt",
            "imageMemoryLimitMB": 256,
            "imageFileTransfer": false,
            "enableSixelImages": true,
            "enableKittyImages": true
          },
          "agentDetection": {
            "enabled": true,
            "oscNotifications": true,
            "patternMatching": true,
            "timingHeuristics": true,
            "idleTimeoutSeconds": 5
          },
          "codeReview": {
            "autoShowOnSessionEnd": true
          },
          "notifications": {
            "macosNotifications": true,
            "sound": true,
            "badgeOnTab": true,
            "flashTab": true,
            "showDockBadge": true,
            "soundFinished": "Sounds/cocxy-finished.caf",
            "soundAttention": "Sounds/cocxy-attention.caf",
            "soundError": "Sounds/cocxy-error.caf"
          },
          "quickTerminal": {
            "enabled": true,
            "hotkey": "cmd+grave",
            "position": "top",
            "heightPercentage": 40,
            "hideOnDeactivate": true,
            "workingDirectory": "~",
            "animationDuration": 0.15,
            "screen": "mouse"
          },
          "keybindings": {
            "newTab": "cmd+t",
            "closeTab": "cmd+w",
            "nextTab": "cmd+shift+]",
            "prevTab": "cmd+shift+[",
            "splitVertical": "cmd+d",
            "splitHorizontal": "cmd+shift+d",
            "gotoAttention": "cmd+shift+u",
            "toggleQuickTerminal": "cmd+grave"
          },
          "sessions": {
            "autoSave": true,
            "autoSaveInterval": 30,
            "restoreOnLaunch": true
          }
        }
        """

        let data = Data(legacyJson.utf8)
        let decoded = try JSONDecoder().decode(CocxyConfig.self, from: data)
        #expect(decoded.appearance.rateLimitIndicatorEnabled == true)
    }

    // MARK: - Project overrides do not drop the flag

    @Test
    func projectOverridesPreserveRateLimitIndicatorEnabled() {
        // The flag is global (a user UI preference, not a project
        // setting). The merge in `applying(projectOverrides:)` must
        // round-trip the field unchanged regardless of which override
        // fields the project supplies.
        let base = CocxyConfig.defaults
        let disabledAppearance = AppearanceConfig(
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
            rateLimitIndicatorEnabled: false
        )
        let rootWithDisabled = CocxyConfig(
            general: base.general,
            appearance: disabledAppearance,
            terminal: base.terminal,
            agentDetection: base.agentDetection,
            codeReview: base.codeReview,
            notifications: base.notifications,
            quickTerminal: base.quickTerminal,
            keybindings: base.keybindings,
            sessions: base.sessions
        )

        let overrides = ProjectConfig(
            fontSize: 18,
            windowPadding: 12
        )

        let merged = rootWithDisabled.applying(projectOverrides: overrides)
        #expect(merged.appearance.rateLimitIndicatorEnabled == false)
        #expect(merged.appearance.fontSize == 18)
    }
}
