// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPanelViewModelSwiftTestingTests.swift - Agent panel state contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentPanelViewModel")
@MainActor
struct AgentPanelViewModelSwiftTestingTests {

    @Test("disabled Agent Mode refuses prompt without invoking runner")
    func disabledAgentModeRefusesPrompt() async throws {
        let runner = RecordingAgentPromptRunner(result: AgentLoopResult(
            messages: [],
            stopReason: .completed
        ))
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: false),
            runner: runner
        )

        viewModel.promptDraft = "Inspect the repository"
        await viewModel.submitPrompt()

        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.state == .disabled)
        #expect(viewModel.statusText == "Agent Mode is disabled.")
        #expect(await runner.prompts.isEmpty)
    }

    @Test("submitting prompt runs provider and publishes completed messages")
    func submitPromptRunsProviderAndPublishesMessages() async throws {
        let messages = [
            AgentMessage(id: "u1", role: .user, content: "What changed?"),
            AgentMessage(id: "a1", role: .assistant, content: "Two files changed."),
        ]
        let runner = RecordingAgentPromptRunner(result: AgentLoopResult(
            messages: messages,
            stopReason: .completed
        ))
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true),
            runner: runner
        )

        viewModel.promptDraft = "  What changed?  "
        await viewModel.submitPrompt()

        #expect(viewModel.promptDraft.isEmpty)
        #expect(viewModel.messages == messages)
        #expect(viewModel.state == .idle)
        #expect(viewModel.statusText == "Completed.")
        #expect(await runner.prompts == ["What changed?"])
    }

    @Test("permission stop reason becomes approval state")
    func permissionStopReasonBecomesApprovalState() async throws {
        let result = AgentLoopResult(
            messages: [AgentMessage(id: "a1", role: .assistant, content: "I need to run tests.")],
            stopReason: .permissionRequired(.commandApprovalRequired(command: "swift test"))
        )
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true),
            runner: RecordingAgentPromptRunner(result: result)
        )

        viewModel.promptDraft = "Run tests"
        await viewModel.submitPrompt()

        #expect(viewModel.state == .awaitingApproval("Approve command: swift test"))
        #expect(viewModel.statusText == "Approve command: swift test")
    }

    @Test("empty prompts do not invoke runner")
    func emptyPromptsDoNotInvokeRunner() async throws {
        let runner = RecordingAgentPromptRunner(result: AgentLoopResult(
            messages: [],
            stopReason: .completed
        ))
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true),
            runner: runner
        )

        viewModel.promptDraft = " \n\t "
        await viewModel.submitPrompt()

        #expect(viewModel.state == .idle)
        #expect(await runner.prompts.isEmpty)
    }

    @Test("runner errors become failed state")
    func runnerErrorsBecomeFailedState() async throws {
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true),
            runner: ThrowingAgentPromptRunner()
        )

        viewModel.promptDraft = "Explain this"
        await viewModel.submitPrompt()

        #expect(viewModel.state == .failed("Provider unavailable."))
        #expect(viewModel.statusText == "Provider unavailable.")
    }
}

private actor RecordingAgentPromptRunner: AgentPromptRunning {
    private let result: AgentLoopResult
    private(set) var prompts: [String] = []

    init(result: AgentLoopResult) {
        self.result = result
    }

    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        prompts.append(prompt)
        return result
    }
}

private struct ThrowingAgentPromptRunner: AgentPromptRunning {
    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        throw AgentPanelViewModelError.providerUnavailable
    }
}
