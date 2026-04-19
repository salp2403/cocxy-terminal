// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraEnabledRoundTripTests.swift - TOML round-trip coverage for the
// aurora-enabled appearance key.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService — aurora-enabled TOML round-trip")
struct AuroraEnabledRoundTripTests {

    // MARK: - Helpers

    /// Bundles a `ConfigService` plus its in-memory provider so tests can
    /// read what was written without touching disk.
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

    // MARK: - Default

    @Test
    func defaultConfigHasAuroraDisabled() {
        let defaults = CocxyConfig.defaults
        #expect(defaults.appearance.auroraEnabled == false)
    }

    @Test
    func defaultTomlTemplateContainsAuroraEnabledFalse() {
        let generated = ConfigService.generateDefaultToml()
        #expect(generated.contains("aurora-enabled = false"))
    }

    // MARK: - Round-trip

    @Test
    func tomlRoundTripPreservesTrueValue() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        aurora-enabled = true
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.auroraEnabled == true)
    }

    @Test
    func tomlRoundTripPreservesFalseValue() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        aurora-enabled = false
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.auroraEnabled == false)
    }

    // MARK: - Tolerant parsing

    @Test
    func missingKeyProducesFalseDefault() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.auroraEnabled == false)
    }

    @Test
    func invalidTypeFallsBackToFalse() throws {
        // Non-boolean values for a Bool key should silently fall back to
        // the default (false) instead of crashing. Mirrors the tolerant
        // contract used by every other parser in ConfigService.
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        aurora-enabled = "yes"
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.auroraEnabled == false)
    }

    @Test
    func emptyAppearanceSectionProducesFalse() throws {
        let toml = """
        [appearance]
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.auroraEnabled == false)
    }

    // MARK: - Generated TOML round-trip

    @Test
    func generatedTomlWithAuroraEnabledTogglePreservesValue() throws {
        // Simulates Preferences writing a toggled config back to disk:
        // start from the default template, flip the flag, then reload.
        let base = ConfigService.generateDefaultToml()
        let toggled = base.replacingOccurrences(
            of: "aurora-enabled = false",
            with: "aurora-enabled = true"
        )
        let config = try loadConfig(from: toggled)
        #expect(config.appearance.auroraEnabled == true)
    }

    // MARK: - Decoder backwards compatibility

    @Test
    func legacyJsonWithoutKeyDecodesAsFalse() throws {
        // Simulate a CocxyConfig persisted before the new key existed.
        // The appearance section omits auroraEnabled, mirroring the shape
        // produced by older session JSON snapshots that still round-trip
        // through the current decoder.
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
        #expect(decoded.appearance.auroraEnabled == false)
    }

    // MARK: - Project overrides do not drop the flag

    @Test
    func projectOverridesPreserveAuroraEnabled() {
        // The `applying(projectOverrides:)` helper rebuilds AppearanceConfig
        // to merge per-project overrides. Aurora is a global flag (not
        // per-project) so it must round-trip unchanged through that merge
        // regardless of which override fields the project supplies.
        let base = CocxyConfig.defaults
        let enabledAppearance = AppearanceConfig(
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
            auroraEnabled: true
        )
        let rootWithAurora = CocxyConfig(
            general: base.general,
            appearance: enabledAppearance,
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

        let merged = rootWithAurora.applying(projectOverrides: overrides)
        #expect(merged.appearance.auroraEnabled == true)
        #expect(merged.appearance.fontSize == 18)
    }
}
