// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("Agent native pattern projection")
struct AgentNativePatternProjectionSwiftTestingTests {

    @Test("default agent configs project stable native CocxyCore patterns")
    func defaultConfigsProjectExpectedNativePatterns() {
        let compiled = AgentConfigService.defaultAgentConfigs().map(AgentConfigService.compile)
        let patterns = AgentConfigService.nativeSemanticPatterns(from: compiled)

        let hasCodexLaunch = patterns.contains {
            $0.type == .agentLaunch && $0.mode == .prefix && $0.text == "codex"
        }
        #expect(hasCodexLaunch)

        let hasCodexBanner = patterns.contains {
            $0.type == .agentLaunch && $0.mode == .contains && $0.text == "Welcome to Codex"
        }
        #expect(hasCodexBanner)

        let hasClaudeBanner = patterns.contains {
            $0.type == .agentLaunch && $0.mode == .contains && $0.text == "Claude Code v"
        }
        #expect(hasClaudeBanner)

        let hasFinishedPrompt = patterns.contains {
            $0.type == .agentFinished && $0.mode == .suffix && $0.text == ">"
        }
        #expect(hasFinishedPrompt)
    }

    @Test("projection stays conservative for regex-heavy launch patterns")
    func projectionSkipsBroadRegexPatterns() {
        let compiled = AgentConfigService.defaultAgentConfigs().map(AgentConfigService.compile)
        let patterns = AgentConfigService.nativeSemanticPatterns(from: compiled)

        let hasBroadPython = patterns.contains {
            $0.type == .agentLaunch && $0.mode == .prefix && $0.text == "python"
        }
        #expect(!hasBroadPython)
    }
}
