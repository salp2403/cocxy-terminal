// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TransparencyChromeThemeRoundTripTests.swift - TOML round-trip coverage
// for the transparency-chrome-theme appearance key.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService — transparency-chrome-theme TOML round-trip")
struct TransparencyChromeThemeRoundTripTests {

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
    func defaultConfigHasFollowSystemTransparencyTheme() {
        let defaults = CocxyConfig.defaults
        #expect(defaults.appearance.transparencyChromeTheme == .followSystem)
    }

    @Test
    func defaultTomlTemplateContainsFollowSystem() {
        let generated = ConfigService.generateDefaultToml()
        #expect(generated.contains("transparency-chrome-theme = \"follow-system\""))
    }

    // MARK: - Round-trip

    @Test
    func tomlRoundTripPreservesLightValue() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        transparency-chrome-theme = "light"
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.transparencyChromeTheme == .light)
    }

    @Test
    func tomlRoundTripPreservesDarkValue() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        transparency-chrome-theme = "dark"
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.transparencyChromeTheme == .dark)
    }

    @Test
    func tomlRoundTripPreservesFollowSystemValue() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        transparency-chrome-theme = "follow-system"
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.transparencyChromeTheme == .followSystem)
    }

    // MARK: - Tolerant parsing

    @Test
    func unknownValueFallsBackToFollowSystem() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        transparency-chrome-theme = "sepia"
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.transparencyChromeTheme == .followSystem)
    }

    @Test
    func missingKeyProducesFollowSystemDefault() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.transparencyChromeTheme == .followSystem)
    }

    @Test
    func invalidTypeFallsBackToFollowSystem() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        transparency-chrome-theme = 42
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.transparencyChromeTheme == .followSystem)
    }

    @Test
    func emptyAppearanceSectionProducesFollowSystem() throws {
        let toml = """
        [appearance]
        """
        let config = try loadConfig(from: toml)
        #expect(config.appearance.transparencyChromeTheme == .followSystem)
    }

    // MARK: - Decoder backwards compatibility

    @Test
    func legacyJsonWithoutKeyDecodesAsFollowSystem() throws {
        // Simulate a CocxyConfig persisted before the new key existed.
        // The appearance section omits transparencyChromeTheme, mirroring
        // the shape produced by older session JSON snapshots that still
        // round-trip through the current decoder.
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
        #expect(decoded.appearance.transparencyChromeTheme == .followSystem)
    }
}
