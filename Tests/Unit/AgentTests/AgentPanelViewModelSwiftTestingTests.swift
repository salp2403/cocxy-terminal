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
        let request = AgentToolApprovalRequest(
            call: AgentToolCall(
                id: "call-run",
                toolID: "run_command",
                arguments: ["command": .string("swift test")]
            ),
            reason: .commandApprovalRequired(command: "swift test"),
            preview: AgentToolApprovalPreview(
                kind: .command,
                title: "Approve command",
                body: "swift test"
            )
        )
        let result = AgentLoopResult(
            messages: [AgentMessage(id: "a1", role: .assistant, content: "I need to run tests.")],
            stopReason: .permissionRequired(request)
        )
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true),
            runner: RecordingApprovalAgentPromptRunner(
                result: result,
                approvedResult: AgentLoopResult(messages: [], stopReason: .completed)
            )
        )

        viewModel.promptDraft = "Run tests"
        await viewModel.submitPrompt()

        #expect(viewModel.state == .awaitingApproval("Approve command: swift test"))
        #expect(viewModel.statusText == "Approve command: swift test")
        #expect(viewModel.pendingApproval == request)
        #expect(viewModel.canApprovePendingTool)
    }

    @Test("approving pending tool resumes runner and clears approval state")
    func approvingPendingToolResumesRunnerAndClearsApprovalState() async throws {
        let request = AgentToolApprovalRequest(
            call: AgentToolCall(
                id: "call-write",
                toolID: "write_file",
                arguments: [
                    "path": .string("Sources/App.swift"),
                    "content": .string("let value = 2\n"),
                ]
            ),
            reason: .diffPreviewRequired(toolID: "write_file"),
            preview: AgentToolApprovalPreview(
                kind: .diff,
                title: "Review changes to Sources/App.swift",
                body: "-let value = 1\n+let value = 2\n"
            )
        )
        let waitingMessages = [
            AgentMessage(id: "u1", role: .user, content: "Update file"),
            AgentMessage(id: "a1", role: .assistant, content: "I need to edit a file."),
        ]
        let completedMessages = waitingMessages + [
            AgentMessage(id: "t1", role: .tool, content: "{}", toolName: "write_file", toolCallID: "call-write"),
            AgentMessage(id: "a2", role: .assistant, content: "Updated."),
        ]
        let runner = RecordingApprovalAgentPromptRunner(
            result: AgentLoopResult(messages: waitingMessages, stopReason: .permissionRequired(request)),
            approvedResult: AgentLoopResult(messages: completedMessages, stopReason: .completed)
        )
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true),
            runner: runner
        )

        viewModel.promptDraft = "Update file"
        await viewModel.submitPrompt()
        await viewModel.approvePendingTool()

        #expect(viewModel.pendingApproval == nil)
        #expect(viewModel.messages == completedMessages)
        #expect(viewModel.state == .idle)
        #expect(viewModel.statusText == "Completed.")
        #expect(await runner.approvedRequests == [request])
        #expect(await runner.approvedUserInputs == [nil])
    }

    @Test("answering pending user question resumes runner with typed response")
    func answeringPendingUserQuestionResumesRunnerWithTypedResponse() async throws {
        let request = AgentToolApprovalRequest(
            call: AgentToolCall(
                id: "call-ask",
                toolID: "ask_user",
                arguments: ["prompt": .string("Which branch should I use?")]
            ),
            reason: .userInputRequired(toolID: "ask_user"),
            preview: AgentToolApprovalPreview(
                kind: .userInput,
                title: "Agent requested input",
                body: "Which branch should I use?"
            )
        )
        let waitingMessages = [
            AgentMessage(id: "u1", role: .user, content: "Prepare the change"),
            AgentMessage(id: "a1", role: .assistant, content: "I need clarification."),
        ]
        let completedMessages = waitingMessages + [
            AgentMessage(id: "t1", role: .tool, content: "{}", toolName: "ask_user", toolCallID: "call-ask"),
            AgentMessage(id: "a2", role: .assistant, content: "Using main."),
        ]
        let runner = RecordingApprovalAgentPromptRunner(
            result: AgentLoopResult(messages: waitingMessages, stopReason: .permissionRequired(request)),
            approvedResult: AgentLoopResult(messages: completedMessages, stopReason: .completed)
        )
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true),
            runner: runner
        )

        viewModel.promptDraft = "Prepare the change"
        await viewModel.submitPrompt()
        #expect(!viewModel.canApprovePendingTool)

        viewModel.pendingApprovalResponseDraft = "  Use main.  "
        await viewModel.approvePendingTool()

        #expect(viewModel.pendingApproval == nil)
        #expect(viewModel.pendingApprovalResponseDraft.isEmpty)
        #expect(viewModel.messages == completedMessages)
        #expect(viewModel.state == .idle)
        #expect(await runner.approvedRequests == [request])
        #expect(await runner.approvedUserInputs == ["Use main."])
    }

    @Test("rejecting pending tool clears approval without invoking runner")
    func rejectingPendingToolClearsApprovalWithoutInvokingRunner() async throws {
        let request = AgentToolApprovalRequest(
            call: AgentToolCall(id: "call-run", toolID: "run_command", arguments: ["command": .string("swift test")]),
            reason: .commandApprovalRequired(command: "swift test"),
            preview: AgentToolApprovalPreview(kind: .command, title: "Approve command", body: "swift test")
        )
        let runner = RecordingApprovalAgentPromptRunner(
            result: AgentLoopResult(messages: [], stopReason: .permissionRequired(request)),
            approvedResult: AgentLoopResult(messages: [], stopReason: .completed)
        )
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true),
            runner: runner
        )

        viewModel.promptDraft = "Run tests"
        await viewModel.submitPrompt()
        viewModel.rejectPendingTool()

        #expect(viewModel.pendingApproval == nil)
        #expect(viewModel.state == .idle)
        #expect(viewModel.statusText == "Request rejected.")
        #expect(await runner.approvedRequests.isEmpty)
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

private actor RecordingApprovalAgentPromptRunner: AgentApprovalRunning {
    private let result: AgentLoopResult
    private let approvedResult: AgentLoopResult
    private(set) var approvedRequests: [AgentToolApprovalRequest] = []
    private(set) var approvedUserInputs: [String?] = []

    init(result: AgentLoopResult, approvedResult: AgentLoopResult) {
        self.result = result
        self.approvedResult = approvedResult
    }

    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        result
    }

    func approve(
        request: AgentToolApprovalRequest,
        userInput: String?,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        approvedRequests.append(request)
        approvedUserInputs.append(userInput)
        return approvedResult
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
