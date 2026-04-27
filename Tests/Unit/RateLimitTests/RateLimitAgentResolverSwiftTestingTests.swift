// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("RateLimitAgentResolver")
struct RateLimitAgentResolverSwiftTestingTests {

    @Test("resolver maps canonical agent identifiers to provider kinds")
    func mapsCanonicalIdentifiers() {
        #expect(RateLimitAgentResolver.kind(name: "claude-code") == .claude)
        #expect(RateLimitAgentResolver.kind(name: "codex-cli") == .codex)
        #expect(RateLimitAgentResolver.kind(name: "gemini-cli") == .gemini)
        #expect(RateLimitAgentResolver.kind(name: "aider") == .aider)
    }

    @Test("resolver also accepts display names when the canonical id is generic")
    func mapsDisplayNames() {
        #expect(RateLimitAgentResolver.kind(name: "agent", displayName: "Claude Code") == .claude)
        #expect(RateLimitAgentResolver.kind(name: "agent", displayName: "Codex CLI") == .codex)
    }

    @Test("unknown agents do not activate any rate-limit provider")
    func unknownAgentReturnsNil() {
        #expect(RateLimitAgentResolver.kind(name: "shell", displayName: "Shell") == nil)
    }

    @Test("detected agent overload preserves launch metadata and maps only identity")
    func detectedAgentOverload() {
        let detected = DetectedAgent(
            name: "claude-code",
            displayName: "Claude Code",
            launchCommand: "claude",
            startedAt: Date()
        )

        #expect(RateLimitAgentResolver.kind(for: detected) == .claude)
    }
}
