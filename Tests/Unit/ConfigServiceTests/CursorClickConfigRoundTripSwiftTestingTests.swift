// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("ConfigService - cursor click-to-move")
struct CursorClickConfigRoundTripSwiftTestingTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?

        init(content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    @Test("default config enables cursor click-to-move")
    func defaultConfigEnablesCursorClickToMove() {
        #expect(TerminalConfig.defaults.cursorClickToMove)
        #expect(ConfigService.generateDefaultToml().contains("cursor-click-to-move = true"))
    }

    @Test("TOML can disable cursor click-to-move")
    func tomlCanDisableCursorClickToMove() throws {
        let provider = InMemoryProvider(content: """
        [terminal]
        cursor-click-to-move = false
        """)
        let service = ConfigService(fileProvider: provider)

        try service.reload()

        #expect(!service.current.terminal.cursorClickToMove)
    }

    @Test("invalid values fall back to enabled")
    func invalidValuesFallBackToEnabled() throws {
        let provider = InMemoryProvider(content: """
        [terminal]
        cursor-click-to-move = "sometimes"
        """)
        let service = ConfigService(fileProvider: provider)

        try service.reload()

        #expect(service.current.terminal.cursorClickToMove)
    }
}
