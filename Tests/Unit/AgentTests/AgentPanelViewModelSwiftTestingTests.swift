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

    @Test("submitting image attachments forwards processed images to attachment runner")
    func submitImageAttachmentsForwardsProcessedImages() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingAttachmentAgentPromptRunner(result: AgentLoopResult(
            messages: [],
            stopReason: .completed
        ))
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true, preferredProvider: .openai),
            runner: runner,
            attachmentStorage: AgentAttachmentStorage(rootDirectory: root)
        )

        try viewModel.attachImageData(Self.pngData, suggestedFilename: "diagram.png")
        let attachedBeforeSubmit = try #require(viewModel.imageAttachments.first)

        viewModel.promptDraft = "  What does this image show?  "
        await viewModel.submitPrompt()

        let forwardedAttachments = await runner.imageAttachments
        #expect(viewModel.promptDraft.isEmpty)
        #expect(viewModel.imageAttachments.isEmpty)
        #expect(viewModel.statusText == "Completed.")
        #expect(await runner.prompts == ["What does this image show?"])
        #expect(forwardedAttachments.count == 1)
        #expect(forwardedAttachments.first?.displayName == "diagram.png")
        #expect(forwardedAttachments.first?.filePath == attachedBeforeSubmit.filePath)
    }

    @Test("image-only prompts use a safe default prompt")
    func imageOnlyPromptUsesDefaultPrompt() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingAttachmentAgentPromptRunner(result: AgentLoopResult(
            messages: [],
            stopReason: .completed
        ))
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true, preferredProvider: .anthropic),
            runner: runner,
            attachmentStorage: AgentAttachmentStorage(rootDirectory: root)
        )

        try viewModel.attachImageData(Self.pngData, suggestedFilename: "screenshot.png")
        await viewModel.submitPrompt()

        #expect(await runner.prompts == ["Please analyze the attached image."])
        #expect(await runner.imageAttachments.count == 1)
    }

    @Test("image attachments require a provider with vision support")
    func imageAttachmentsRequireVisionProvider() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingAttachmentAgentPromptRunner(result: AgentLoopResult(
            messages: [],
            stopReason: .completed
        ))
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true, preferredProvider: .foundationModelsOnDevice),
            runner: runner,
            attachmentStorage: AgentAttachmentStorage(rootDirectory: root)
        )

        try viewModel.attachImageData(Self.pngData, suggestedFilename: "local.png")
        await viewModel.submitPrompt()

        #expect(viewModel.state == .failed("Foundation Models does not support image attachments in Agent Mode."))
        #expect(viewModel.statusText == "Foundation Models does not support image attachments in Agent Mode.")
        #expect(!viewModel.imageAttachments.isEmpty)
        #expect(await runner.prompts.isEmpty)
    }

    @Test("selected skills are passed as system context without changing user prompt")
    func selectedSkillsArePassedAsSystemContext() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSkill(
            id: "review-pr",
            name: "Review PR",
            summary: "Review risks first.",
            body: "Lead with correctness risks.",
            in: root
        )
        let runner = RecordingAgentPromptRunner(result: AgentLoopResult(
            messages: [],
            stopReason: .completed
        ))
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true),
            runner: runner,
            skillRegistry: SkillRegistry(directories: [SkillDirectory(url: root, source: .project)])
        )

        #expect(viewModel.availableSkills.map(\.id) == ["review-pr"])

        viewModel.setSkill("review-pr", selected: true)
        viewModel.promptDraft = "  Inspect this change.  "
        await viewModel.submitPrompt()

        let histories = await runner.histories
        #expect(await runner.prompts == ["Inspect this change."])
        #expect(histories.count == 1)
        #expect(histories.first?.count == 1)
        #expect(histories.first?.first?.role == .system)
        #expect(histories.first?.first?.content.contains("Selected local skills:") == true)
        #expect(histories.first?.first?.content.contains("Lead with correctness risks.") == true)
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

    @Test("computer use approval exposes per-action status without typed text")
    func computerUseApprovalExposesPerActionStatusWithoutTypedText() async throws {
        let request = AgentToolApprovalRequest(
            call: AgentToolCall(
                id: "call-type",
                toolID: "computer_type_text",
                arguments: ["text": .string("secret-token")]
            ),
            reason: .computerUseApprovalRequired(toolID: "computer_type_text"),
            preview: AgentToolApprovalPreview(
                kind: .computerUse,
                title: "Approve computer action",
                body: "computer_type_text\ntext: 12 characters"
            )
        )
        let runner = RecordingApprovalAgentPromptRunner(
            result: AgentLoopResult(messages: [], stopReason: .permissionRequired(request)),
            approvedResult: AgentLoopResult(messages: [], stopReason: .completed)
        )
        let viewModel = AgentPanelViewModel(
            configuration: AgentModeConfig(enabled: true),
            runner: runner
        )

        viewModel.promptDraft = "Type locally"
        await viewModel.submitPrompt()

        let status = try #require(viewModel.computerUseStatus)
        #expect(status.phase == .awaitingApproval)
        #expect(status.title == "Typing pending")
        #expect(status.detail == "12 characters")
        #expect(status.systemImage == "keyboard")
        #expect(status.accessibilityLabel == "Computer action pending: type text, 12 characters")
        #expect(!status.accessibilityLabel.contains("secret-token"))

        let spanish = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )
        #expect(status.localizedTitle(using: spanish) == "Escritura pendiente")
        #expect(status.localizedDetail(using: spanish) == "12 caracteres")
        #expect(
            status.localizedAccessibilityLabel(using: spanish)
                == "Acción de computadora pendiente: escribir texto, 12 caracteres"
        )
    }

    @Test("computer use status names running screenshot and mouse actions")
    func computerUseStatusNamesRunningScreenshotAndMouseActions() throws {
        let screenshotRequest = AgentToolApprovalRequest(
            call: AgentToolCall(id: "shot", toolID: "computer_screenshot"),
            reason: .computerUseApprovalRequired(toolID: "computer_screenshot"),
            preview: AgentToolApprovalPreview(kind: .computerUse, title: "Approve computer action", body: "shot")
        )
        let mouseRequest = AgentToolApprovalRequest(
            call: AgentToolCall(
                id: "move",
                toolID: "computer_move_mouse",
                arguments: ["x": .number(10), "y": .number(20.5)]
            ),
            reason: .computerUseApprovalRequired(toolID: "computer_move_mouse"),
            preview: AgentToolApprovalPreview(kind: .computerUse, title: "Approve computer action", body: "move")
        )
        let clickRequest = AgentToolApprovalRequest(
            call: AgentToolCall(
                id: "click",
                toolID: "computer_click",
                arguments: [
                    "button": .string("right"),
                    "clickCount": .number(2),
                    "x": .number(10),
                    "y": .number(20.5),
                ]
            ),
            reason: .computerUseApprovalRequired(toolID: "computer_click"),
            preview: AgentToolApprovalPreview(kind: .computerUse, title: "Approve computer action", body: "click")
        )

        let screenshot = try #require(AgentComputerUseStatus(request: screenshotRequest, phase: .running))
        #expect(screenshot.title == "Capturing screen")
        #expect(screenshot.detail == "Main display")
        #expect(screenshot.accessibilityLabel == "Computer action running: capture screenshot, main display")

        let mouse = try #require(AgentComputerUseStatus(request: mouseRequest, phase: .running))
        #expect(mouse.title == "Moving mouse")
        #expect(mouse.detail == "x 10, y 20.5")
        #expect(mouse.accessibilityLabel == "Computer action running: move mouse, x 10, y 20.5")

        let click = try #require(AgentComputerUseStatus(request: clickRequest, phase: .awaitingApproval))
        #expect(click.title == "Mouse click pending")
        #expect(click.detail == "2 right clicks at x 10, y 20.5")
        #expect(click.accessibilityLabel == "Computer action pending: 2 right clicks at x 10, y 20.5")

        let spanish = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )
        #expect(screenshot.localizedTitle(using: spanish) == "Capturando pantalla")
        #expect(screenshot.localizedDetail(using: spanish) == "Pantalla principal")
        #expect(
            screenshot.localizedAccessibilityLabel(using: spanish)
                == "Acción de computadora en ejecución: capturar pantalla, pantalla principal"
        )
        #expect(mouse.localizedTitle(using: spanish) == "Moviendo mouse")
        #expect(mouse.localizedDetail(using: spanish) == "x 10, y 20.5")
        #expect(
            mouse.localizedAccessibilityLabel(using: spanish)
                == "Acción de computadora en ejecución: mover mouse, x 10, y 20.5"
        )
        #expect(click.localizedTitle(using: spanish) == "Clic de mouse pendiente")
        #expect(click.localizedDetail(using: spanish) == "2 clics derecho en x 10, y 20.5")
        #expect(
            click.localizedAccessibilityLabel(using: spanish)
                == "Acción de computadora pendiente: 2 clics derecho, x 10, y 20.5"
        )
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

    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
    )!
}

private actor RecordingAgentPromptRunner: AgentPromptRunning {
    private let result: AgentLoopResult
    private(set) var prompts: [String] = []
    private(set) var histories: [[AgentMessage]] = []

    init(result: AgentLoopResult) {
        self.result = result
    }

    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        prompts.append(prompt)
        histories.append(history)
        return result
    }
}

private actor RecordingAttachmentAgentPromptRunner: AgentAttachmentPromptRunning {
    private let result: AgentLoopResult
    private(set) var prompts: [String] = []
    private(set) var histories: [[AgentMessage]] = []
    private(set) var imageAttachments: [AgentImageAttachment] = []

    init(result: AgentLoopResult) {
        self.result = result
    }

    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig,
        imageAttachments: [AgentImageAttachment]
    ) async throws -> AgentLoopResult {
        prompts.append(prompt)
        histories.append(history)
        self.imageAttachments.append(contentsOf: imageAttachments)
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

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocxy-agent-panel-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func localizationBundle() -> Bundle? {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
}

private func writeSkill(
    id: String,
    name: String,
    summary: String,
    body: String,
    in root: URL
) throws {
    let directory = root.appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try """
    ---
    id: \(id)
    name: \(name)
    description: \(summary)
    ---
    # \(name)

    \(body)
    """.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
}
