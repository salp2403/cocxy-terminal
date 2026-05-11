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
        #expect(defaults.sandbox.pluginsStrict)
        #expect(defaults.sandbox.agentsIsolated)
        #expect(defaults.sandbox.mcpIsolated)
        #expect(defaults.sandbox.auditLogEnabled)
        #expect(defaults.sandbox.warnOnGrant)
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
        #expect(toml.contains("[security.sandbox]"))
        #expect(toml.contains("plugins-strict = true"))
        #expect(toml.contains("agents-isolated = true"))
        #expect(toml.contains("mcp-isolated = true"))
        #expect(toml.contains("audit-log-enabled = true"))
        #expect(toml.contains("warn-on-grant = true"))
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

        [security.sandbox]
        plugins-strict = false
        agents-isolated = false
        mcp-isolated = false
        audit-log-enabled = false
        warn-on-grant = false
        """)

        #expect(config.security.requireSignedTemplates)
        #expect(config.security.requireSignedMacros)
        #expect(config.security.requireSignedPlugins)
        #expect(!config.security.warnOnUnsigned)
        #expect(config.security.trustOnFirstUse)
        #expect(!config.security.sandbox.pluginsStrict)
        #expect(!config.security.sandbox.agentsIsolated)
        #expect(!config.security.sandbox.mcpIsolated)
        #expect(!config.security.sandbox.auditLogEnabled)
        #expect(!config.security.sandbox.warnOnGrant)
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

        [security.sandbox]
        plugins-strict = "yes"
        agents-isolated = 1
        mcp-isolated = []
        audit-log-enabled = "always"
        warn-on-grant = "sure"
        """)

        #expect(missing.security == .defaults)
        #expect(malformed.security == .defaults)
    }
}
