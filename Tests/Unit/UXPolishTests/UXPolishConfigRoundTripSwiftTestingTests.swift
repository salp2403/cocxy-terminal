// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// UXPolishConfigRoundTripSwiftTestingTests.swift - Config pipeline coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("UX polish config round-trip")
struct UXPolishConfigRoundTripSwiftTestingTests {

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

    @Test("default TOML includes UX polish section")
    func defaultTomlIncludesUXPolishSection() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[ux-polish]"))
        #expect(toml.contains("always-show-shortcut-hints = false"))
        #expect(toml.contains("shortcut-hint-debug-overlay = false"))
    }

    @Test("TOML preserves explicit UX polish values")
    func tomlPreservesExplicitValues() throws {
        let config = try loadConfig(from: """
        [ux-polish]
        always-show-shortcut-hints = true
        shortcut-hint-debug-overlay = true
        shortcut-hint-offset-x = 12
        shortcut-hint-offset-y = -4
        shortcut-hint-scale = 1.25
        """)

        #expect(config.uxPolish.alwaysShowShortcutHints == true)
        #expect(config.uxPolish.shortcutHintDebugOverlay == true)
        #expect(config.uxPolish.shortcutHintOffsetX == 12)
        #expect(config.uxPolish.shortcutHintOffsetY == -4)
        #expect(config.uxPolish.shortcutHintScale == 1.25)
    }

    @Test("malformed UX polish values fall back without changing terminal defaults")
    func malformedValuesFallBackSafely() throws {
        let config = try loadConfig(from: """
        [ux-polish]
        always-show-shortcut-hints = "yes"
        shortcut-hint-debug-overlay = "no"
        shortcut-hint-offset-x = "large"
        shortcut-hint-scale = -10
        """)

        #expect(config.uxPolish == .defaults)
        #expect(config.general == .defaults)
        #expect(config.terminal == .defaults)
    }
}
