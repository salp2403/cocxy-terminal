// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPanelViewModel.swift - View model for built-in Agent Mode panel.

import Combine
import Foundation

protocol AgentPromptRunning: Sendable {
    func run(prompt: String, history: [AgentMessage]) async throws -> AgentLoopResult
}

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
        state = .running
        statusText = "Running..."

        do {
            let result = try await runner.run(prompt: prompt, history: messages)
            messages = result.messages
            applyStopReason(result.stopReason)
        } catch {
            let description = error.localizedDescription
            state = .failed(description)
            statusText = description
        }
    }

    private func applyStopReason(_ stopReason: AgentLoopStopReason) {
        switch stopReason {
        case .completed:
            state = .idle
            statusText = "Completed."
        case .maxIterationsReached:
            state = .failed("Stopped at max iterations.")
            statusText = "Stopped at max iterations."
        case .permissionRequired(let reason):
            let text = approvalText(for: reason)
            state = .awaitingApproval(text)
            statusText = text
        case .denied(let reason):
            let text = deniedText(for: reason)
            state = .failed(text)
            statusText = text
        case .protocolFailure(let error):
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
        }
    }
}
