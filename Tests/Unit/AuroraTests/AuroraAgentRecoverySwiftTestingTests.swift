// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("Aurora agent recovery from visible buffers")
@MainActor
struct AuroraAgentRecoverySwiftTestingTests {

    private var compiledDefaults: [CompiledAgentConfig] {
        AgentConfigService.defaultAgentConfigs().map(AgentConfigService.compile)
    }

    @Test("Claude banner is recovered as Claude Code, not stale Codex")
    func claudeBannerIsRecoveredAsClaude() {
        let identifier = MainWindowController.mostRecentAuroraAgentIdentifier(
            in: [
                "OpenAI Codex (v0.121.0)",
                "Claude Code v2.1.14",
                "Opus 4.7 (1M context) with xhigh effort · Claude Max",
            ],
            compiledConfigs: compiledDefaults
        )

        #expect(identifier == "claude")
    }

    @Test("Most recent visible launch marker wins")
    func mostRecentVisibleLaunchMarkerWins() {
        let identifier = MainWindowController.mostRecentAuroraAgentIdentifier(
            in: [
                "Claude Code v2.1.14",
                "OpenAI Codex (v0.121.0)",
            ],
            compiledConfigs: compiledDefaults
        )

        #expect(identifier == "codex")
    }

    @Test("Plain terminal output does not fabricate an agent")
    func plainTerminalOutputDoesNotFabricateAgent() {
        let identifier = MainWindowController.mostRecentAuroraAgentIdentifier(
            in: [
                "Galf@MacBook-Pro ~/sisocs-v3 (main●)$ ls",
                "README.md Sources Tests",
            ],
            compiledConfigs: compiledDefaults
        )

        #expect(identifier == nil)
    }

    @Test("Visible full-screen Claude TUI can seed an idle surface")
    func visibleClaudeTUISeedsIdleSurface() {
        let identifier = MainWindowController.visibleAuroraAgentIdentifier(
            in: [
                "",
                "Claude Code v2.1.14",
                "Opus 4.7 (1M context) with xhigh effort · Claude Max",
                "~/sisocs-v3",
                "",
                "› auto mode on (shift+tab to cycle)",
            ],
            compiledConfigs: compiledDefaults
        )

        #expect(identifier == "claude")
    }

    @Test("Visible stale Codex banner is ignored after shell prompt returns")
    func visibleStaleCodexBannerAfterShellPromptIsIgnored() {
        let identifier = MainWindowController.visibleAuroraAgentIdentifier(
            in: [
                "OpenAI Codex (v0.121.0)",
                "model: gpt-5.4 xhigh",
                "Tip: Try the Codex App.",
                "Galf@MacBook-Pro ~/sisocs-v3 (main●)$",
            ],
            compiledConfigs: compiledDefaults
        )

        #expect(identifier == nil)
    }

    @Test("Returned shell prompt is detected without treating agent prompts as shell")
    func returnedShellPromptDetectionStaysNarrow() {
        #expect(
            MainWindowController.visibleAuroraBufferHasReturnedShellPrompt([
                "Claude Code v2.1.14",
                "› auto mode on (shift+tab to cycle)",
            ]) == false,
            "Agent TUI prompts must not clear a live Claude/Codex session"
        )

        #expect(
            MainWindowController.visibleAuroraBufferHasReturnedShellPrompt([
                "OpenAI Codex (v0.121.0)",
                "Tip: Try the Codex App.",
                "Galf@MacBook-Pro ~/sisocs-v3 (main●)$",
            ]) == true,
            "A real shell prompt below an old banner marks the visible agent state as stale"
        )
    }

    @Test("Returned shell prompt suppresses history fallback so closed agents do not revive")
    func returnedShellPromptSuppressesHistoryFallback() {
        let fallback = MainWindowController.auroraHistoryFallbackAgentIdentifier(
            visibleAgent: nil,
            visibleLines: [
                "OpenAI Codex (v0.121.0)",
                "To continue this session, run codex resume 019da97",
                "Galf@MacBook-Pro ~/sisocs-v3 (main●)$",
            ],
            historyLines: [
                "OpenAI Codex (v0.121.0)",
                "model: gpt-5.4 xhigh",
                "› /review on my current changes",
            ],
            currentCarriesAgent: true,
            compiledConfigs: compiledDefaults
        )

        #expect(fallback == nil)
    }

    @Test("History fallback is still available when a live full-screen TUI scrolls its banner away")
    func historyFallbackSurvivesWhenNoShellPromptReturned() {
        let fallback = MainWindowController.auroraHistoryFallbackAgentIdentifier(
            visibleAgent: nil,
            visibleLines: [
                "› continue implementation",
                "gpt-5.4 xhigh · ~/sisocs-v3",
            ],
            historyLines: [
                "OpenAI Codex (v0.121.0)",
                "model: gpt-5.4 xhigh",
                "› continue implementation",
            ],
            currentCarriesAgent: true,
            compiledConfigs: compiledDefaults
        )

        #expect(fallback == "codex")
    }

    @Test("Visible live Codex TUI can seed an idle surface")
    func visibleCodexTUISeedsIdleSurface() {
        let identifier = MainWindowController.visibleAuroraAgentIdentifier(
            in: [
                "",
                "OpenAI Codex (v0.121.0)",
                "model: gpt-5.4 xhigh   /model to change",
                "directory: ~/sisocs-v3",
                "",
                "› find and fix a bug in @filename",
            ],
            compiledConfigs: compiledDefaults
        )

        #expect(identifier == "codex")
    }

    @Test("Visible sibling Codex and Claude panes keep their own identities")
    func visibleSiblingAgentBuffersResolveIndependently() {
        let claude = MainWindowController.visibleAuroraAgentIdentifier(
            in: [
                "Claude Code v2.1.14",
                "Opus 4.7 (1M context) with xhigh effort · Claude Max",
                "› auto mode on (shift+tab to cycle)",
            ],
            compiledConfigs: compiledDefaults
        )
        let codex = MainWindowController.visibleAuroraAgentIdentifier(
            in: [
                "OpenAI Codex (v0.121.0)",
                "model: gpt-5.4 xhigh",
                "› find and fix a bug in @filename",
            ],
            compiledConfigs: compiledDefaults
        )

        #expect(claude == "claude")
        #expect(codex == "codex")
    }
}
