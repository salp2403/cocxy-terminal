// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Agent detection full parity")
struct AgentDetectionFullParitySwiftTestingTests {

    @Test("DetectedAgent decodes older payloads by falling back displayName to name")
    func detectedAgentBackCompatDecode() throws {
        let json = """
        {
          "name": "gemini-cli",
          "launchCommand": "gemini",
          "startedAt": "2026-04-13T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let agent = try decoder.decode(DetectedAgent.self, from: Data(json.utf8))

        #expect(agent.name == "gemini-cli")
        #expect(agent.displayName == "gemini-cli")
        #expect(agent.launchCommand == "gemini")
    }

    @Test("AgentConfigService resolves display names from aliases")
    func displayNameResolutionUsesAliases() {
        let service = AgentConfigService()

        #expect(service.displayName(forAgentIdentifier: "claude") == "Claude Code")
        #expect(service.displayName(forAgentIdentifier: "codex") == "Codex CLI")
        #expect(service.displayName(forAgentIdentifier: "gemini") == "Gemini CLI")
        #expect(service.displayName(forAgentIdentifier: "kiro-cli") == "Kiro")
        #expect(service.displayName(forAgentIdentifier: "opencode") == "OpenCode")
    }

    @Test("Default agent configs include improved parity patterns and timeouts")
    func defaultParityPatternsPresent() throws {
        let defaults = AgentConfigService.defaultAgentConfigs()

        let codex = try #require(defaults.first(where: { $0.name == "codex" }))
        #expect(codex.launchPatterns.contains("Welcome to Codex"))
        #expect(codex.waitingPatterns.contains("Enter to confirm"))
        #expect(codex.idleTimeoutOverride == 8)

        let aider = try #require(defaults.first(where: { $0.name == "aider" }))
        #expect(aider.launchPatterns.contains("Aider v\\d+\\.\\d+"))
        #expect(aider.waitingPatterns.contains("^aider>"))
        #expect(aider.idleTimeoutOverride == 10)

        let gemini = try #require(defaults.first(where: { $0.name == "gemini-cli" }))
        #expect(gemini.launchPatterns.contains("Gemini CLI v\\d+"))
        #expect(gemini.waitingPatterns.contains("Waiting for user confirmation"))
        #expect(gemini.idleTimeoutOverride == 8)

        let kiro = try #require(defaults.first(where: { $0.name == "kiro" }))
        #expect(kiro.launchPatterns.contains("Welcome to Kiro"))
        #expect(kiro.errorPatterns.contains("rate limit reached"))
        #expect(kiro.idleTimeoutOverride == 8)

        let opencode = try #require(defaults.first(where: { $0.name == "opencode" }))
        #expect(opencode.launchPatterns.contains("Loading plugins"))
        #expect(opencode.finishedIndicators.contains("✓"))
        #expect(opencode.idleTimeoutOverride == 8)
    }
}
