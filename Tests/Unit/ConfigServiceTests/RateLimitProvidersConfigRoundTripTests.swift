// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - rate-limit providers TOML round-trip")
struct RateLimitProvidersConfigRoundTripTests {

    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        init(_ content: String?) { self.content = content }
        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func loadConfig(from toml: String) throws -> CocxyConfig {
        let provider = InMemoryProvider(toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service.current
    }

    @Test("defaults enable the ten local usage providers from the plan")
    func defaultsEnableExpectedProviders() {
        let defaults = CocxyConfig.defaults.rateLimit

        #expect(defaults.enabledProviders == [
            .claude,
            .codex,
            .cursor,
            .copilot,
            .opencode,
            .amp,
            .factory,
            .kimi,
            .minimax,
            .zai,
        ])
        #expect(defaults.autoDetect == true)
        #expect(defaults.oauthRefreshIntervalMinutes == 50)
    }

    @Test("default TOML template contains the rate-limit provider section")
    func defaultTomlContainsRateLimitSection() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[rate-limit]"))
        #expect(toml.contains("enabled-providers = [\"claude\", \"codex\", \"cursor\", \"copilot\", \"opencode\", \"amp\", \"factory\", \"kimi\", \"minimax\", \"zai\"]"))
        #expect(toml.contains("auto-detect = true"))
        #expect(toml.contains("oauth-refresh-interval-minutes = 50"))
    }

    @Test("TOML preserves explicit providers and refresh interval")
    func tomlPreservesExplicitProviders() throws {
        let config = try loadConfig(from: """
        [rate-limit]
        enabled-providers = ["cursor", "copilot", "cursor", "unknown"]
        auto-detect = false
        oauth-refresh-interval-minutes = 5
        """)

        #expect(config.rateLimit.enabledProviders == [.cursor, .copilot])
        #expect(config.rateLimit.autoDetect == false)
        #expect(config.rateLimit.oauthRefreshIntervalMinutes == 5)
    }

    @Test("missing or malformed rate-limit section falls back safely")
    func missingOrMalformedFallsBackSafely() throws {
        let missing = try loadConfig(from: "[appearance]\ntheme = \"catppuccin-mocha\"")
        let malformed = try loadConfig(from: """
        [rate-limit]
        enabled-providers = "cursor"
        auto-detect = "yes"
        oauth-refresh-interval-minutes = -4
        """)

        #expect(missing.rateLimit == .defaults)
        #expect(malformed.rateLimit == .defaults)
    }
}
