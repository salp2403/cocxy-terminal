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
}

extension AgentPanelViewModelError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "Provider unavailable."
        }
    }
}

@MainActor
final class AgentPanelViewModel: ObservableObject {
    @Published var promptDraft: String = ""
    @Published private(set) var messages: [AgentMessage] = []
    @Published private(set) var state: AgentPanelState = .idle
    @Published private(set) var statusText: String = "Ready."
    @Published private(set) var pendingApproval: AgentToolApprovalRequest?
    @Published var pendingApprovalResponseDraft: String = ""

    private var configuration: AgentModeConfig
    private let runner: any AgentPromptRunning

    init(configuration: AgentModeConfig, runner: any AgentPromptRunning) {
        self.configuration = configuration
        self.runner = runner
        if !configuration.enabled {
            state = .disabled
            statusText = "Agent Mode is disabled."
        }
    }

    var canSubmit: Bool {
        configuration.enabled
            && state != .running
            && !promptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    func submitPrompt() async {
        let prompt = promptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        guard configuration.enabled else {
            state = .disabled
            statusText = "Agent Mode is disabled."
            return
        }

        guard state != .running else { return }

        promptDraft = ""
        pendingApproval = nil
        pendingApprovalResponseDraft = ""
        state = .running
        statusText = "Running..."

        do {
            let result = try await runner.run(
                prompt: prompt,
                history: messages,
                configuration: configuration
            )
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
