// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputConfigRoundTripTests.swift - TOML coverage for `[rich-input]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - rich input TOML round-trip")
struct RichInputConfigRoundTripTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?

        init(content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }

        func writeConfigFile(_ content: String) throws {
            self.content = content
        }
    }

    @Test("defaults match documented rich input behavior")
    func defaultsMatchDocumentedBehavior() {
        let config = CocxyConfig.defaults

        #expect(config.richInput.enabled == true)
        #expect(config.richInput.autoShowOnMultilinePaste == true)
        #expect(config.richInput.defaultShortcut == "cmd+shift+i")
        #expect(config.richInput.attachmentsCacheTTLDays == 7)
        #expect(config.richInput.attachmentsMaxSizeMB == 25)
        #expect(config.richInput.preserveDraftsPerTab == true)
        #expect(config.keybindings.shortcutString(for: KeybindingActionCatalog.richInputComposer.id) == "cmd+shift+i")
    }

    @Test("default TOML template includes rich input section")
    func defaultTomlTemplateIncludesRichInputSection() {
        let generated = ConfigService.generateDefaultToml()

        #expect(generated.contains("[rich-input]"))
        #expect(generated.contains("auto-show-on-multiline-paste = true"))
        #expect(generated.contains("default-shortcut = \"cmd+shift+i\""))
        #expect(generated.contains("attachments-cache-ttl-days = 7"))
        #expect(generated.contains("attachments-max-size-mb = 25"))
    }

    @Test("TOML round trip preserves every rich input key")
    func tomlRoundTripPreservesEveryRichInputKey() throws {
        let service = ConfigService(fileProvider: InMemoryProvider(content: """
        [rich-input]
        enabled = false
        auto-show-on-multiline-paste = false
        default-shortcut = "cmd+alt+i"
        attachments-cache-ttl-days = 3
        attachments-max-size-mb = 12
        preserve-drafts-per-tab = false
        """))

        try service.reload()
        let config = service.current

        #expect(config.richInput.enabled == false)
        #expect(config.richInput.autoShowOnMultilinePaste == false)
        #expect(config.richInput.defaultShortcut == "cmd+alt+i")
        #expect(config.richInput.attachmentsCacheTTLDays == 3)
        #expect(config.richInput.attachmentsMaxSizeMB == 12)
        #expect(config.richInput.preserveDraftsPerTab == false)
        #expect(config.keybindings.shortcutString(for: KeybindingActionCatalog.richInputComposer.id) == "cmd+alt+i")
    }

    @Test("invalid numeric values are clamped for rich input")
    func invalidNumericValuesAreClamped() throws {
        let service = ConfigService(fileProvider: InMemoryProvider(content: """
        [rich-input]
        attachments-cache-ttl-days = -10
        attachments-max-size-mb = 9000
        """))

        try service.reload()
        let config = service.current

        #expect(config.richInput.attachmentsCacheTTLDays == 1)
        #expect(config.richInput.attachmentsMaxSizeMB == 500)
    }

    @Test("explicit keybinding override wins over rich input shortcut fallback")
    func explicitKeybindingOverrideWinsOverRichInputShortcutFallback() throws {
        let service = ConfigService(fileProvider: InMemoryProvider(content: """
        [rich-input]
        default-shortcut = "cmd+alt+i"

        [keybindings]
        "terminal.richInput" = "cmd+ctrl+i"
        """))

        try service.reload()
        let config = service.current

        #expect(config.richInput.defaultShortcut == "cmd+alt+i")
        #expect(config.keybindings.shortcutString(for: KeybindingActionCatalog.richInputComposer.id) == "cmd+ctrl+i")
    }
}
