// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("ConfigService - command corrections TOML round-trip")
struct CommandCorrectionsConfigRoundTripTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        init(content: String? = nil) { self.content = content }
        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func loadConfig(from toml: String) throws -> CocxyConfig {
        let provider = InMemoryProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service.current
    }

    @Test("defaults enable local command corrections safely")
    func defaultsEnableLocalCommandCorrectionsSafely() {
        let defaults = CocxyConfig.defaults.commandCorrections

        #expect(defaults.enabled)
        #expect(defaults.autoShowOnFailure)
        #expect(defaults.editDistanceThreshold == 2)
        #expect(defaults.foundationModelsEnabled)
        #expect(!defaults.agentFallback)
        #expect(defaults.showConfidenceBadge)
        #expect(defaults.maxSuggestionsShown == 3)
    }

    @Test("generated TOML documents command corrections settings")
    func generatedTomlDocumentsCommandCorrectionsSettings() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[command-corrections]"))
        #expect(toml.contains("enabled = true"))
        #expect(toml.contains("edit-distance-threshold = 2"))
        #expect(toml.contains("foundation-models-enabled = true"))
        #expect(toml.contains("agent-fallback = false"))
    }

    @Test("TOML preserves explicit command correction settings")
    func tomlPreservesExplicitCommandCorrectionSettings() throws {
        let config = try loadConfig(from: """
        [command-corrections]
        enabled = false
        edit-distance-threshold = 1
        foundation-models-enabled = false
        agent-fallback = true
        auto-show-on-failure = false
        show-confidence-badge = false
        max-suggestions-shown = 5
        """)

        #expect(!config.commandCorrections.enabled)
        #expect(config.commandCorrections.editDistanceThreshold == 1)
        #expect(!config.commandCorrections.foundationModelsEnabled)
        #expect(config.commandCorrections.agentFallback)
        #expect(!config.commandCorrections.autoShowOnFailure)
        #expect(!config.commandCorrections.showConfidenceBadge)
        #expect(config.commandCorrections.maxSuggestionsShown == 5)
    }

    @Test("malformed command correction settings fall back safely")
    func malformedCommandCorrectionSettingsFallBackSafely() throws {
        let config = try loadConfig(from: """
        [command-corrections]
        enabled = "yes"
        edit-distance-threshold = -4
        foundation-models-enabled = 1
        agent-fallback = []
        auto-show-on-failure = "sometimes"
        show-confidence-badge = "always"
        max-suggestions-shown = 0
        """)

        #expect(config.commandCorrections == .defaults)
    }
}
