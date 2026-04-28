// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ExperimentalConfigSwiftTestingTests.swift - Feature gate defaults.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ExperimentalConfig")
struct ExperimentalConfigSwiftTestingTests {

    @Test("experimental feature gates default off")
    func defaultsAreOff() {
        #expect(CocxyConfig.defaults.experimental.pipEnabled == false)
        #expect(CocxyConfig.defaults.experimental.ptyDaemonEnabled == false)
    }

    @Test("generated default TOML documents both experimental gates")
    func generatedDefaultTomlIncludesGates() {
        let toml = ConfigService.generateDefaultToml()
        #expect(toml.contains("[experimental]"))
        #expect(toml.contains("pip-enabled = false"))
        #expect(toml.contains("pty-daemon = false"))
    }

    @Test("codable fallback keeps gates off when section is absent")
    func codableFallbackKeepsGatesOff() throws {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CocxyConfig.self, from: data)
        #expect(decoded.experimental == .defaults)
    }
}
