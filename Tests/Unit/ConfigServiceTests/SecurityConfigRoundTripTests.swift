// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("ConfigService - security TOML round-trip")
struct SecurityConfigRoundTripTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?

        init(content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func loadConfig(from toml: String) throws -> CocxyConfig {
        let service = ConfigService(fileProvider: InMemoryProvider(content: toml))
        try service.reload()
        return service.current
    }

    @Test("defaults warn on unsigned artifacts without breaking existing installs")
    func defaultsWarnOnUnsignedArtifactsWithoutBreakingExistingInstalls() {
        let defaults = CocxyConfig.defaults.security

        #expect(!defaults.requireSignedTemplates)
        #expect(!defaults.requireSignedMacros)
        #expect(!defaults.requireSignedPlugins)
        #expect(defaults.warnOnUnsigned)
        #expect(!defaults.trustOnFirstUse)
    }

    @Test("generated TOML documents signature policy")
    func generatedTOMLDocumentsSignaturePolicy() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[security]"))
        #expect(toml.contains("require-signed-templates = false"))
        #expect(toml.contains("require-signed-macros = false"))
        #expect(toml.contains("require-signed-plugins = false"))
        #expect(toml.contains("warn-on-unsigned = true"))
        #expect(toml.contains("trust-on-first-use = false"))
    }

    @Test("TOML preserves explicit security policy")
    func tomlPreservesExplicitSecurityPolicy() throws {
        let config = try loadConfig(from: """
        [security]
        require-signed-templates = true
        require-signed-macros = true
        require-signed-plugins = true
        warn-on-unsigned = false
        trust-on-first-use = true
        """)

        #expect(config.security.requireSignedTemplates)
        #expect(config.security.requireSignedMacros)
        #expect(config.security.requireSignedPlugins)
        #expect(!config.security.warnOnUnsigned)
        #expect(config.security.trustOnFirstUse)
    }

    @Test("missing and malformed security sections fall back safely")
    func missingAndMalformedSecuritySectionsFallBackSafely() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [security]
        require-signed-templates = "yes"
        require-signed-macros = "no"
        require-signed-plugins = 1
        warn-on-unsigned = []
        trust-on-first-use = "never"
        """)

        #expect(missing.security == .defaults)
        #expect(malformed.security == .defaults)
    }
}
