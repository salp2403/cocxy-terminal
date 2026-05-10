// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService - input classifier TOML round-trip")
struct InputClassifierConfigRoundTripTests {
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

    @Test("defaults enable local classifier without auto routing")
    func defaultsEnableLocalClassifierWithoutAutoRouting() {
        let defaults = CocxyConfig.defaults.inputClassifier

        #expect(defaults.enabled)
        #expect(defaults.dangerousCommandWarning)
        #expect(!defaults.autoRouteNaturalLanguage)
        #expect(defaults.localeDetection)
        #expect(defaults.foundationModelsFallback)
    }

    @Test("generated TOML documents input classifier settings")
    func generatedTomlDocumentsInputClassifierSettings() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[input-classifier]"))
        #expect(toml.contains("enabled = true"))
        #expect(toml.contains("dangerous-command-warning = true"))
        #expect(toml.contains("auto-route-natural-language = false"))
        #expect(toml.contains("locale-detection = true"))
        #expect(toml.contains("foundation-models-fallback = true"))
    }

    @Test("TOML preserves explicit input classifier settings")
    func tomlPreservesExplicitInputClassifierSettings() throws {
        let config = try loadConfig(from: """
        [input-classifier]
        enabled = false
        dangerous-command-warning = false
        auto-route-natural-language = true
        locale-detection = false
        foundation-models-fallback = false
        """)

        #expect(!config.inputClassifier.enabled)
        #expect(!config.inputClassifier.dangerousCommandWarning)
        #expect(config.inputClassifier.autoRouteNaturalLanguage)
        #expect(!config.inputClassifier.localeDetection)
        #expect(!config.inputClassifier.foundationModelsFallback)
    }

    @Test("missing and malformed input classifier sections fall back safely")
    func missingAndMalformedInputClassifierSectionsFallBackSafely() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [input-classifier]
        enabled = "yes"
        dangerous-command-warning = "no"
        auto-route-natural-language = "sometimes"
        locale-detection = 1
        foundation-models-fallback = []
        """)

        #expect(missing.inputClassifier == .defaults)
        #expect(malformed.inputClassifier == .defaults)
    }
}
