// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CompletionConfigRoundTripTests.swift - TOML coverage for the `[completions]` section.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService — completions TOML round-trip")
struct CompletionConfigRoundTripTests {
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

    @Test("completion defaults are disabled and local-only")
    func defaultsAreDisabledAndLocalOnly() {
        let defaults = CocxyConfig.defaults.completions

        #expect(defaults.inlineAIEnabled == false)
        #expect(defaults.provider == .foundationModelsOnDevice)
        #expect(defaults.idleDelaySeconds == 0.2)
        #expect(defaults.maxContextUTF16Length == 4_000)
        #expect(defaults.enabledLanguageIDs.contains("swift"))
        #expect(!defaults.enabledLanguageIDs.contains("markdown"))
    }

    @Test("generated default TOML documents disabled inline completions")
    func generatedTomlDocumentsDisabledInlineCompletions() {
        let toml = ConfigService.generateDefaultToml()

        #expect(toml.contains("[completions]"))
        #expect(toml.contains("inline-ai = false"))
        #expect(toml.contains("provider = \"foundation-models-on-device\""))
        #expect(toml.contains("idle-delay-seconds = 0.2"))
    }

    @Test("TOML opt-in preserves normalized languages and clamped context")
    func tomlOptInPreservesNormalizedLanguagesAndClampedContext() throws {
        let config = try loadConfig(from: """
        [completions]
        inline-ai = true
        provider = "foundation-models-on-device"
        idle-delay-seconds = 0.01
        max-context-utf16-length = 999999
        enabled-languages = ["Swift", " python ", "markdown", "swift"]
        """)

        #expect(config.completions.inlineAIEnabled == true)
        #expect(config.completions.provider == .foundationModelsOnDevice)
        #expect(config.completions.idleDelaySeconds == CompletionConfig.minIdleDelaySeconds)
        #expect(config.completions.maxContextUTF16Length == CompletionConfig.maxContextUTF16Length)
        #expect(config.completions.enabledLanguageIDs == ["markdown", "python", "swift"])
    }

    @Test("missing and malformed completion sections fall back safely")
    func missingAndMalformedCompletionSectionsFallbackSafely() throws {
        let missing = try loadConfig(from: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let malformed = try loadConfig(from: """
        [completions]
        inline-ai = "yes"
        provider = "remote"
        idle-delay-seconds = "fast"
        max-context-utf16-length = "large"
        enabled-languages = [1, true]
        """)

        #expect(missing.completions == .defaults)
        #expect(malformed.completions == .defaults)
    }
}
