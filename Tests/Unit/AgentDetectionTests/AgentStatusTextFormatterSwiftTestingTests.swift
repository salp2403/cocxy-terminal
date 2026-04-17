// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Tests for AgentStatusTextFormatter — pure text and bucket helpers used
// by the status bar summary during Fase 3.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentStatusTextFormatter")
struct AgentStatusTextFormatterSwiftTestingTests {

    // MARK: - activeAgentStatusText

    @Test("idle state produces no text")
    func idleProducesNoText() {
        let text = AgentStatusTextFormatter.activeAgentStatusText(
            state: .idle,
            agentName: "Claude Code",
            agentActivity: "ignored"
        )
        #expect(text == nil)
    }

    @Test("launched state renders a starting label")
    func launchedRendersStartingLabel() {
        let text = AgentStatusTextFormatter.activeAgentStatusText(
            state: .launched,
            agentName: "Claude Code",
            agentActivity: nil
        )
        #expect(text == "Claude Code starting...")
    }

    @Test("working with an activity prefers the activity verbatim")
    func workingPrefersActivity() {
        let text = AgentStatusTextFormatter.activeAgentStatusText(
            state: .working,
            agentName: "Claude Code",
            agentActivity: "Read: main.swift"
        )
        #expect(text == "Read: main.swift")
    }

    @Test("working with no activity falls back to a working label")
    func workingWithoutActivityFallsBack() {
        let text = AgentStatusTextFormatter.activeAgentStatusText(
            state: .working,
            agentName: "Claude Code",
            agentActivity: nil
        )
        #expect(text == "Claude Code working")
    }

    @Test("working with a whitespace-only activity falls back to the generic label")
    func workingWithBlankActivityFallsBack() {
        let text = AgentStatusTextFormatter.activeAgentStatusText(
            state: .working,
            agentName: "Claude Code",
            agentActivity: "   \n"
        )
        #expect(text == "Claude Code working")
    }

    @Test("waitingInput renders the waiting label")
    func waitingRendersLabel() {
        let text = AgentStatusTextFormatter.activeAgentStatusText(
            state: .waitingInput,
            agentName: "Codex CLI",
            agentActivity: nil
        )
        #expect(text == "Codex CLI waiting for input")
    }

    @Test("finished renders the finished label")
    func finishedRendersLabel() {
        let text = AgentStatusTextFormatter.activeAgentStatusText(
            state: .finished,
            agentName: "Aider",
            agentActivity: nil
        )
        #expect(text == "Aider finished")
    }

    @Test("error renders the error label")
    func errorRendersLabel() {
        let text = AgentStatusTextFormatter.activeAgentStatusText(
            state: .error,
            agentName: "Gemini CLI",
            agentActivity: nil
        )
        #expect(text == "Gemini CLI error")
    }

    // MARK: - counterBucket

    @Test("working and launched collapse into the same counter bucket")
    func workingAndLaunchedSameBucket() {
        #expect(AgentStatusTextFormatter.counterBucket(for: .working) == .working)
        #expect(AgentStatusTextFormatter.counterBucket(for: .launched) == .working)
    }

    @Test("waitingInput maps to the waiting bucket")
    func waitingMapsToWaitingBucket() {
        #expect(AgentStatusTextFormatter.counterBucket(for: .waitingInput) == .waiting)
    }

    @Test("error maps to the errors bucket")
    func errorMapsToErrorsBucket() {
        #expect(AgentStatusTextFormatter.counterBucket(for: .error) == .errors)
    }

    @Test("finished maps to the finished bucket")
    func finishedMapsToFinishedBucket() {
        #expect(AgentStatusTextFormatter.counterBucket(for: .finished) == .finished)
    }

    @Test("idle produces no counter bucket")
    func idleHasNoBucket() {
        #expect(AgentStatusTextFormatter.counterBucket(for: .idle) == nil)
    }
}
