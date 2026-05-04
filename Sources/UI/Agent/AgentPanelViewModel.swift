// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPanelViewModel.swift - View model for built-in Agent Mode panel.

import Combine
import Foundation

enum AgentPanelState: Sendable, Equatable {
    case idle
    case running
    case disabled
    case awaitingApproval(String)
    case failed(String)
}

enum AgentPanelViewModelError: Error, Sendable, Equatable {
    case providerUnavailable
    case attachmentRunnerUnavailable
    case imageAttachmentsUnsupported(AgentProviderKind)
}

extension AgentPanelViewModelError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "Provider unavailable."
        case .attachmentRunnerUnavailable:
            return "Current Agent runner does not support image attachments."
        case .imageAttachmentsUnsupported(let provider):
            return "\(provider.displayName) does not support image attachments in Agent Mode."
        }
    }
}

struct AgentPanelSkillOption: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let summary: String
    let source: SkillSource
}

struct AgentComputerUseStatus: Sendable, Equatable {
    enum Phase: Sendable, Equatable {
        case awaitingApproval
        case running
    }

    enum Kind: Sendable, Equatable {
        case moveMouse(coordinates: String)
        case click(button: String, count: Int, coordinates: String)
        case typeText(characterCount: Int)
        case screenshot
        case custom(toolID: String)
    }

    let phase: Phase
    let kind: Kind
    let title: String
    let detail: String
    let systemImage: String
    let accessibilityLabel: String

    init?(request: AgentToolApprovalRequest, phase: Phase) {
        guard request.preview.kind == .computerUse else { return nil }
        self.phase = phase

        switch request.call.toolID {
        case "computer_move_mouse":
            let coordinateText = Self.coordinateText(from: request.call)
            self.kind = .moveMouse(coordinates: coordinateText)
            self.systemImage = "cursorarrow.motionlines"
            self.title = phase == .running ? "Moving mouse" : "Mouse move pending"
            self.detail = coordinateText
            self.accessibilityLabel = "Computer action \(phase.accessibilityVerb): move mouse, \(coordinateText)"
        case "computer_click":
            let coordinateText = Self.coordinateText(from: request.call)
            let rawButton = request.call.arguments["button"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let button = rawButton?.isEmpty == false ? rawButton ?? "left" : "left"
            let clickCount = Int(Self.numberValue(request.call.arguments["clickCount"]) ?? 1)
            let normalizedClickCount = max(1, clickCount)
            let clickText = "\(normalizedClickCount) \(button) click\(normalizedClickCount == 1 ? "" : "s")"
            self.kind = .click(button: button, count: normalizedClickCount, coordinates: coordinateText)
            self.systemImage = "cursorarrow.click"
            self.title = phase == .running ? "Clicking mouse" : "Mouse click pending"
            self.detail = "\(clickText) at \(coordinateText)"
            self.accessibilityLabel = "Computer action \(phase.accessibilityVerb): \(clickText) at \(coordinateText)"
        case "computer_type_text":
            let characterCount = request.call.arguments["text"]?.stringValue?.count ?? 0
            let detail = "\(characterCount) character\(characterCount == 1 ? "" : "s")"
            self.kind = .typeText(characterCount: characterCount)
            self.systemImage = "keyboard"
            self.title = phase == .running ? "Typing text" : "Typing pending"
            self.detail = detail
            self.accessibilityLabel = "Computer action \(phase.accessibilityVerb): type text, \(detail)"
        case "computer_screenshot":
            self.kind = .screenshot
            self.systemImage = "camera.viewfinder"
            self.title = phase == .running ? "Capturing screen" : "Screenshot pending"
            self.detail = "Main display"
            self.accessibilityLabel = "Computer action \(phase.accessibilityVerb): capture screenshot, main display"
        default:
            self.kind = .custom(toolID: request.call.toolID)
            self.systemImage = "cursorarrow.click"
            self.title = phase == .running ? "Running computer action" : "Computer action pending"
            self.detail = request.call.toolID
            self.accessibilityLabel = "Computer action \(phase.accessibilityVerb): \(request.call.toolID)"
        }
    }

    func localizedTitle(using localizer: AppLocalizer) -> String {
        switch (kind, phase) {
        case (.moveMouse, .running):
            return localizer.string("agent.panel.computerUse.title.move.running", fallback: "Moving mouse")
        case (.moveMouse, .awaitingApproval):
            return localizer.string("agent.panel.computerUse.title.move.pending", fallback: "Mouse move pending")
        case (.click, .running):
            return localizer.string("agent.panel.computerUse.title.click.running", fallback: "Clicking mouse")
        case (.click, .awaitingApproval):
            return localizer.string("agent.panel.computerUse.title.click.pending", fallback: "Mouse click pending")
        case (.typeText, .running):
            return localizer.string("agent.panel.computerUse.title.type.running", fallback: "Typing text")
        case (.typeText, .awaitingApproval):
            return localizer.string("agent.panel.computerUse.title.type.pending", fallback: "Typing pending")
        case (.screenshot, .running):
            return localizer.string("agent.panel.computerUse.title.screenshot.running", fallback: "Capturing screen")
        case (.screenshot, .awaitingApproval):
            return localizer.string("agent.panel.computerUse.title.screenshot.pending", fallback: "Screenshot pending")
        case (.custom, .running):
            return localizer.string("agent.panel.computerUse.title.custom.running", fallback: "Running computer action")
        case (.custom, .awaitingApproval):
            return localizer.string("agent.panel.computerUse.title.custom.pending", fallback: "Computer action pending")
        }
    }

    func localizedDetail(using localizer: AppLocalizer) -> String {
        switch kind {
        case .moveMouse(let coordinates):
            return coordinates
        case .click(let button, let count, let coordinates):
            let key = count == 1
                ? "agent.panel.computerUse.detail.click.one"
                : "agent.panel.computerUse.detail.click.many"
            let fallback = count == 1
                ? "%d %@ click at %@"
                : "%d %@ clicks at %@"
            return String(
                format: localizer.string(key, fallback: fallback),
                count,
                localizedMouseButton(button, using: localizer),
                coordinates
            )
        case .typeText(let characterCount):
            let key = characterCount == 1
                ? "agent.panel.computerUse.detail.characters.one"
                : "agent.panel.computerUse.detail.characters.many"
            let fallback = characterCount == 1 ? "%d character" : "%d characters"
            return String(format: localizer.string(key, fallback: fallback), characterCount)
        case .screenshot:
            return localizer.string(
                "agent.panel.computerUse.detail.mainDisplay",
                fallback: "Main display"
            )
        case .custom(let toolID):
            return toolID
        }
    }

    func localizedAccessibilityLabel(using localizer: AppLocalizer) -> String {
        let phase = phase.localizedAccessibilityVerb(using: localizer)
        switch kind {
        case .moveMouse(let coordinates):
            return String(
                format: localizer.string(
                    "agent.panel.computerUse.accessibility.move",
                    fallback: "Computer action %@: move mouse, %@"
                ),
                phase,
                coordinates
            )
        case .click(let button, let count, let coordinates):
            return String(
                format: localizer.string(
                    "agent.panel.computerUse.accessibility.click",
                    fallback: "Computer action %@: %@, %@"
                ),
                phase,
                localizedClickText(button: button, count: count, using: localizer),
                coordinates
            )
        case .typeText:
            return String(
                format: localizer.string(
                    "agent.panel.computerUse.accessibility.type",
                    fallback: "Computer action %@: type text, %@"
                ),
                phase,
                localizedDetail(using: localizer)
            )
        case .screenshot:
            return String(
                format: localizer.string(
                    "agent.panel.computerUse.accessibility.screenshot",
                    fallback: "Computer action %@: capture screenshot, %@"
                ),
                phase,
                localizedDetail(using: localizer).lowercased()
            )
        case .custom(let toolID):
            return String(
                format: localizer.string(
                    "agent.panel.computerUse.accessibility.custom",
                    fallback: "Computer action %@: %@"
                ),
                phase,
                toolID
            )
        }
    }

    private func localizedClickText(
        button: String,
        count: Int,
        using localizer: AppLocalizer
    ) -> String {
        let key = count == 1
            ? "agent.panel.computerUse.clickText.one"
            : "agent.panel.computerUse.clickText.many"
        let fallback = count == 1 ? "%d %@ click" : "%d %@ clicks"
        return String(
            format: localizer.string(key, fallback: fallback),
            count,
            localizedMouseButton(button, using: localizer)
        )
    }

    private func localizedMouseButton(_ button: String, using localizer: AppLocalizer) -> String {
        switch button.lowercased() {
        case "left":
            return localizer.string("agent.panel.computerUse.button.left", fallback: button)
        case "right":
            return localizer.string("agent.panel.computerUse.button.right", fallback: button)
        case "middle":
            return localizer.string("agent.panel.computerUse.button.middle", fallback: button)
        default:
            return button
        }
    }

    private static func coordinateText(from call: AgentToolCall) -> String {
        let x = coordinateValue(numberValue(call.arguments["x"]))
        let y = coordinateValue(numberValue(call.arguments["y"]))
        return "x \(x), y \(y)"
    }

    private static func numberValue(_ value: AgentJSONValue?) -> Double? {
        guard case .number(let number) = value else { return nil }
        return number
    }

    private static func coordinateValue(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        if value.rounded(.towardZero) == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

private extension AgentComputerUseStatus.Phase {
    var accessibilityVerb: String {
        switch self {
        case .awaitingApproval:
            return "pending"
        case .running:
            return "running"
        }
    }

    func localizedAccessibilityVerb(using localizer: AppLocalizer) -> String {
        switch self {
        case .awaitingApproval:
            return localizer.string("agent.panel.computerUse.phase.pending", fallback: "pending")
        case .running:
            return localizer.string("agent.panel.computerUse.phase.running", fallback: "running")
        }
    }
}

@MainActor
final class AgentPanelViewModel: ObservableObject {
    @Published var promptDraft: String = ""
    @Published private(set) var availableSkills: [AgentPanelSkillOption] = []
    @Published private(set) var selectedSkillIDs: Set<String> = []
    @Published private(set) var messages: [AgentMessage] = []
    @Published private(set) var state: AgentPanelState = .idle
    @Published private(set) var statusText: String = "Ready."
    @Published private(set) var pendingApproval: AgentToolApprovalRequest?
    @Published private(set) var imageAttachments: [AgentImageAttachment] = []
    @Published var pendingApprovalResponseDraft: String = ""

    private var configuration: AgentModeConfig
    private let runner: any AgentPromptRunning
    private var skillRegistry: SkillRegistry
    private let attachmentStorage: AgentAttachmentStorage
    private let imageProcessor: AgentImageProcessor

    init(
        configuration: AgentModeConfig,
        runner: any AgentPromptRunning,
        skillRegistry: SkillRegistry = .localDefault(),
        attachmentStorage: AgentAttachmentStorage = AgentAttachmentStorage(),
        imageProcessor: AgentImageProcessor = AgentImageProcessor()
    ) {
        self.configuration = configuration
        self.runner = runner
        self.skillRegistry = skillRegistry
        self.attachmentStorage = attachmentStorage
        self.imageProcessor = imageProcessor
        refreshSkills()
        if !configuration.enabled {
            state = .disabled
            statusText = "Agent Mode is disabled."
        }
    }

    var canSubmit: Bool {
        configuration.enabled
            && state != .running
            && (
                !promptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !imageAttachments.isEmpty
            )
    }

    var canApprovePendingTool: Bool {
        guard configuration.enabled,
              state != .running,
              let pendingApproval,
              runner is any AgentApprovalRunning
        else {
            return false
        }

        if pendingApproval.preview.kind == .userInput {
            return !pendingApprovalResponseDraft
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
        return true
    }

    var selectedSkillsCount: Int {
        selectedSkillIDs.count
    }

    var computerUseStatus: AgentComputerUseStatus? {
        guard let pendingApproval else { return nil }
        let phase: AgentComputerUseStatus.Phase = state == .running ? .running : .awaitingApproval
        return AgentComputerUseStatus(request: pendingApproval, phase: phase)
    }

    func updateConfiguration(_ configuration: AgentModeConfig) {
        self.configuration = configuration
        if configuration.enabled {
            if state == .disabled {
                state = .idle
                statusText = "Ready."
            }
        } else {
            state = .disabled
            statusText = "Agent Mode is disabled."
            pendingApproval = nil
            pendingApprovalResponseDraft = ""
        }
    }

    func updateSkillRegistry(_ skillRegistry: SkillRegistry) {
        self.skillRegistry = skillRegistry
        refreshSkills()
    }

    func isSkillSelected(_ skillID: String) -> Bool {
        selectedSkillIDs.contains(skillID)
    }

    func setSkill(_ skillID: String, selected: Bool) {
        guard availableSkills.contains(where: { $0.id == skillID }) else { return }
        if selected {
            selectedSkillIDs.insert(skillID)
        } else {
            selectedSkillIDs.remove(skillID)
        }
    }

    func attachImageData(_ data: Data, suggestedFilename: String? = nil) throws {
        let processed = try imageProcessor.process(data: data)
        let attachment = try attachmentStorage.store(processed, originalFilename: suggestedFilename)
        imageAttachments.append(attachment)
        statusText = "\(imageAttachments.count) image\(imageAttachments.count == 1 ? "" : "s") attached."
    }

    func attachImageFile(_ fileURL: URL) throws {
        let processed = try imageProcessor.process(fileURL: fileURL)
        let attachment = try attachmentStorage.store(
            processed,
            originalFilename: fileURL.lastPathComponent
        )
        imageAttachments.append(attachment)
        statusText = "\(imageAttachments.count) image\(imageAttachments.count == 1 ? "" : "s") attached."
    }

    func removeImageAttachment(id: String) {
        guard let index = imageAttachments.firstIndex(where: { $0.id == id }) else { return }
        let attachment = imageAttachments.remove(at: index)
        attachmentStorage.remove(attachment)
        statusText = imageAttachments.isEmpty
            ? "Ready."
            : "\(imageAttachments.count) image\(imageAttachments.count == 1 ? "" : "s") attached."
    }

    func handleAttachmentError(_ error: Error) {
        let description = error.localizedDescription
        state = .failed(description)
        statusText = description
    }

    func submitPrompt() async {
        let prompt = promptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = imageAttachments
        guard !prompt.isEmpty || !attachments.isEmpty else { return }

        guard configuration.enabled else {
            state = .disabled
            statusText = "Agent Mode is disabled."
            return
        }

        guard state != .running else { return }

        if !attachments.isEmpty, !(runner is any AgentAttachmentPromptRunning) {
            let description = AgentPanelViewModelError.attachmentRunnerUnavailable.localizedDescription
            state = .failed(description)
            statusText = description
            return
        }
        if !attachments.isEmpty, !configuration.preferredProvider.supportsAgentImageAttachments {
            let description = AgentPanelViewModelError
                .imageAttachmentsUnsupported(configuration.preferredProvider)
                .localizedDescription
            state = .failed(description)
            statusText = description
            return
        }

        let effectiveHistory: [AgentMessage]
        do {
            effectiveHistory = try historyWithSelectedSkills()
        } catch {
            let description = error.localizedDescription
            state = .failed(description)
            statusText = description
            return
        }

        promptDraft = ""
        imageAttachments = []
        pendingApproval = nil
        pendingApprovalResponseDraft = ""
        state = .running
        statusText = "Running..."

        do {
            let effectivePrompt = prompt.isEmpty ? "Please analyze the attached image." : prompt
            let result: AgentLoopResult
            if let attachmentRunner = runner as? any AgentAttachmentPromptRunning {
                result = try await attachmentRunner.run(
                    prompt: effectivePrompt,
                    history: effectiveHistory,
                    configuration: configuration,
                    imageAttachments: attachments
                )
            } else {
                result = try await runner.run(
                    prompt: effectivePrompt,
                    history: effectiveHistory,
                    configuration: configuration
                )
            }
            messages = result.messages
            applyStopReason(result.stopReason)
        } catch {
            let description = error.localizedDescription
            state = .failed(description)
            statusText = description
        }
    }

    func approvePendingTool() async {
        guard let request = pendingApproval else { return }
        let response = pendingApprovalResponseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if request.preview.kind == .userInput, response.isEmpty {
            return
        }
        guard configuration.enabled else {
            state = .disabled
            statusText = "Agent Mode is disabled."
            pendingApproval = nil
            pendingApprovalResponseDraft = ""
            return
        }
        guard let approvalRunner = runner as? any AgentApprovalRunning else {
            let text = "Approval is unavailable for this Agent runner."
            state = .failed(text)
            statusText = text
            return
        }

        state = .running
        statusText = "Running approved tool..."

        do {
            let result = try await approvalRunner.approve(
                request: request,
                userInput: request.preview.kind == .userInput ? response : nil,
                history: messages,
                configuration: configuration
            )
            pendingApproval = nil
            pendingApprovalResponseDraft = ""
            messages = result.messages
            applyStopReason(result.stopReason)
        } catch {
            let description = error.localizedDescription
            state = .failed(description)
            statusText = description
        }
    }

    func rejectPendingTool() {
        guard pendingApproval != nil else { return }
        pendingApproval = nil
        pendingApprovalResponseDraft = ""
        state = configuration.enabled ? .idle : .disabled
        statusText = configuration.enabled ? "Request rejected." : "Agent Mode is disabled."
    }

    private func refreshSkills() {
        do {
            let loadedSkills = try skillRegistry.loadSkills()
            availableSkills = loadedSkills.map {
                AgentPanelSkillOption(
                    id: $0.id,
                    name: $0.name,
                    summary: $0.summary,
                    source: $0.source
                )
            }
            let availableIDs = Set(availableSkills.map(\.id))
            selectedSkillIDs = selectedSkillIDs.intersection(availableIDs)
        } catch {
            availableSkills = []
            selectedSkillIDs = []
            if configuration.enabled {
                statusText = "Failed to load skills: \(error.localizedDescription)"
            }
        }
    }

    private func historyWithSelectedSkills() throws -> [AgentMessage] {
        guard !selectedSkillIDs.isEmpty else {
            return messages
        }

        let invocation = try SkillInvoker(registry: skillRegistry)
            .makeInvocation(skillIDs: Array(selectedSkillIDs))
        let context = """
        Selected local skills:
        \(invocation.instructions)
        """
        return messages + [
            AgentMessage(
                id: "agent-panel-selected-skills-\(invocation.skillIDs.joined(separator: "-"))",
                role: .system,
                content: context
            ),
        ]
    }

    private func applyStopReason(_ stopReason: AgentLoopStopReason) {
        switch stopReason {
        case .completed:
            pendingApproval = nil
            pendingApprovalResponseDraft = ""
            state = .idle
            statusText = "Completed."
        case .maxIterationsReached:
            pendingApproval = nil
            pendingApprovalResponseDraft = ""
            state = .failed("Stopped at max iterations.")
            statusText = "Stopped at max iterations."
        case .permissionRequired(let request):
            pendingApproval = request
            pendingApprovalResponseDraft = ""
            let text = approvalText(for: request.reason)
            state = .awaitingApproval(text)
            statusText = text
        case .denied(let reason):
            pendingApproval = nil
            pendingApprovalResponseDraft = ""
            let text = deniedText(for: reason)
            state = .failed(text)
            statusText = text
        case .protocolFailure(let error):
            pendingApproval = nil
            pendingApprovalResponseDraft = ""
            let text = "Tool protocol error: \(error)"
            state = .failed(text)
            statusText = text
        }
    }

    private func approvalText(for reason: AgentToolPromptReason) -> String {
        switch reason {
        case .commandApprovalRequired(let command):
            return "Approve command: \(command)"
        case .diffPreviewRequired(let toolID):
            return "Review diff for \(toolID)."
        case .computerUseApprovalRequired(let toolID):
            return "Approve computer action \(toolID)."
        case .externalToolApprovalRequired(let toolID):
            return "Approve external tool \(toolID)."
        case .userInputRequired(let toolID):
            return "Agent requested input for \(toolID)."
        }
    }

    private func deniedText(for reason: AgentToolDenyReason) -> String {
        switch reason {
        case .missingCommand(let toolID):
            return "Blocked \(toolID) without a command."
        case .dangerousCommand(let command):
            return "Blocked dangerous command: \(command)"
        case .previewUnavailable(let toolID):
            return "Blocked \(toolID) because a preview could not be generated."
        }
    }
}
