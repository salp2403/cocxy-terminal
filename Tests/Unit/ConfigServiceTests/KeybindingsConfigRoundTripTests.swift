// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeybindingsConfigRoundTripTests.swift - TOML parse/generate coverage for keybindings.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("KeybindingsConfig TOML round trip")
struct KeybindingsConfigRoundTripTests {

    /// Trivial in-memory provider shared with the tests.
    final class InMemoryFileProvider: ConfigFileProviding, @unchecked Sendable {
        var stored: String?
        func readConfigFile() -> String? { stored }
        func writeConfigFile(_ content: String) throws { stored = content }
    }

    // MARK: - Parsing

    @Test func parsesLegacyKebabCaseSection() throws {
        let provider = InMemoryFileProvider()
        provider.stored = """
        [keybindings]
        new-tab = "cmd+shift+t"
        close-tab = "cmd+shift+w"
        next-tab = "cmd+shift+]"
        prev-tab = "cmd+shift+["
        split-vertical = "cmd+shift+d"
        split-horizontal = "cmd+d"
        goto-attention = "cmd+shift+u"
        toggle-quick-terminal = "cmd+grave"
        """

        let service = ConfigService(fileProvider: provider)
        try service.reload()

        #expect(service.current.keybindings.newTab == "cmd+shift+t")
        #expect(service.current.keybindings.closeTab == "cmd+shift+w")
        #expect(service.current.keybindings.customOverrides.isEmpty)
    }

    @Test func parsesDottedCatalogIds() throws {
        // Pick values that are different from catalog defaults so the
        // parser actually stores them as customOverrides.
        let provider = InMemoryFileProvider()
        provider.stored = """
        [keybindings]
        "split.close" = "cmd+ctrl+shift+x"
        "navigation.splitLeft" = "cmd+shift+left"
        """

        let service = ConfigService(fileProvider: provider)
        try service.reload()

        let custom = service.current.keybindings.customOverrides
        #expect(custom["split.close"] == "cmd+ctrl+shift+x")
        #expect(custom["navigation.splitLeft"] == "cmd+shift+left")
    }

    @Test func dottedIdOverridesLegacyFieldForSameAction() throws {
        let provider = InMemoryFileProvider()
        provider.stored = """
        [keybindings]
        new-tab = "cmd+t"
        "tab.new" = "cmd+shift+n"
        """

        let service = ConfigService(fileProvider: provider)
        try service.reload()

        #expect(service.current.keybindings.newTab == "cmd+shift+n")
        #expect(service.current.keybindings.customOverrides["tab.new"] == nil)
    }

    @Test func ignoresUnknownIds() throws {
        let provider = InMemoryFileProvider()
        provider.stored = """
        [keybindings]
        "nonsense.unknown" = "cmd+alt+z"
        """

        let service = ConfigService(fileProvider: provider)
        try service.reload()

        #expect(service.current.keybindings.customOverrides["nonsense.unknown"] == nil)
    }

    @Test func missingSectionFallsBackToDefaults() throws {
        let provider = InMemoryFileProvider()
        provider.stored = ""

        let service = ConfigService(fileProvider: provider)
        try service.reload()

        #expect(service.current.keybindings == KeybindingsConfig.defaults)
    }

    // MARK: - Generation

    @Test func tomlSectionEmitsLegacyFields() {
        let config = KeybindingsConfig.defaults
        let section = config.tomlSection()

        #expect(section.hasPrefix("[keybindings]"))
        #expect(section.contains("new-tab = \"cmd+t\""))
        #expect(section.contains("split-horizontal = \"cmd+d\""))
        #expect(section.contains("split-vertical = \"cmd+shift+d\""))
        #expect(section.contains("toggle-quick-terminal = \"cmd+grave\""))
    }

    @Test func tomlSectionEmitsCustomOverridesSorted() {
        let custom = [
            "navigation.splitLeft": "cmd+alt+left",
            "split.close": "cmd+ctrl+w",
        ]
        let config = KeybindingsConfig(
            newTab: "cmd+t",
            closeTab: "cmd+w",
            nextTab: "cmd+shift+]",
            prevTab: "cmd+shift+[",
            splitVertical: "cmd+shift+d",
            splitHorizontal: "cmd+d",
            gotoAttention: "cmd+shift+u",
            toggleQuickTerminal: "cmd+grave",
            customOverrides: custom
        )
        let section = config.tomlSection()

        let navLine = "\"navigation.splitLeft\" = \"cmd+alt+left\""
        let closeLine = "\"split.close\" = \"cmd+ctrl+w\""
        #expect(section.contains(navLine))
        #expect(section.contains(closeLine))

        // Sorted alphabetically: navigation.splitLeft comes before split.close.
        let navIndex = section.range(of: navLine)!.lowerBound
        let closeIndex = section.range(of: closeLine)!.lowerBound
        #expect(navIndex < closeIndex)
    }

    @Test func fullRoundTripThroughConfigService() throws {
        // Use non-default values so customOverrides actually carries them.
        let provider = InMemoryFileProvider()
        provider.stored = """
        [general]
        shell = "/bin/zsh"
        working-directory = "~"

        [keybindings]
        new-tab = "cmd+t"
        "split.close" = "cmd+ctrl+shift+x"
        "navigation.splitRight" = "cmd+ctrl+shift+right"
        """

        let service = ConfigService(fileProvider: provider)
        try service.reload()

        // Re-emit the section and re-read to confirm stability.
        let emitted = service.current.keybindings.tomlSection()
        provider.stored = emitted

        let service2 = ConfigService(fileProvider: provider)
        try service2.reload()
        #expect(service2.current.keybindings.customOverrides["split.close"] == "cmd+ctrl+shift+x")
        #expect(service2.current.keybindings.customOverrides["navigation.splitRight"] == "cmd+ctrl+shift+right")
    }
}

@Suite("KeybindingsConfig helpers")
struct KeybindingsConfigHelperTests {

    @Test func shortcutStringPrefersLegacyField() {
        let config = KeybindingsConfig(
            newTab: "cmd+shift+n",
            closeTab: "cmd+w",
            nextTab: "cmd+shift+]",
            prevTab: "cmd+shift+[",
            splitVertical: "cmd+shift+d",
            splitHorizontal: "cmd+d",
            gotoAttention: "cmd+shift+u",
            toggleQuickTerminal: "cmd+grave",
            customOverrides: ["tab.new": "cmd+alt+t"]
        )
        // Legacy wins over customOverrides entry.
        #expect(config.shortcutString(for: KeybindingActionCatalog.tabNew.id) == "cmd+shift+n")
    }

    @Test func shortcutStringFallsBackToCatalogDefault() {
        let config = KeybindingsConfig.defaults
        // splitClose is not in the legacy fields and has no custom override.
        let resolved = config.shortcutString(for: KeybindingActionCatalog.splitClose.id)
        #expect(resolved == KeybindingActionCatalog.splitClose.defaultShortcut.canonical)
    }

    @Test func isCustomizedTrueWhenOverrideDiffers() {
        let config = KeybindingsConfig(
            newTab: "cmd+shift+n",   // different from default cmd+t
            closeTab: "cmd+w",
            nextTab: "cmd+shift+]",
            prevTab: "cmd+shift+[",
            splitVertical: "cmd+shift+d",
            splitHorizontal: "cmd+d",
            gotoAttention: "cmd+shift+u",
            toggleQuickTerminal: "cmd+grave"
        )
        #expect(config.isCustomized(KeybindingActionCatalog.tabNew.id) == true)
        #expect(config.isCustomized(KeybindingActionCatalog.tabClose.id) == false)
    }
}
