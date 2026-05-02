// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentToolPermission.swift - Agent Mode permission decisions.

import Foundation

/// A single tool request before execution.
struct AgentToolInvocation: Sendable, Equatable {
    let toolID: String
    let capability: AgentToolCapability
    let command: String?

    init(toolID: String, capability: AgentToolCapability, command: String? = nil) {
        self.toolID = AgentToolDescriptor.normalizedID(toolID)
        self.capability = capability
        self.command = command
    }
}

enum AgentToolPromptReason: Sendable, Equatable {
    case diffPreviewRequired(toolID: String)
    case commandApprovalRequired(command: String)
    case externalToolApprovalRequired(toolID: String)
    case userInputRequired(toolID: String)
}

enum AgentToolApprovalPreviewKind: String, Sendable, Equatable {
    case diff
    case command
    case externalTool
    case userInput
}

struct AgentToolApprovalPreview: Sendable, Equatable {
    let kind: AgentToolApprovalPreviewKind
    let title: String
    let body: String
}

struct AgentToolApprovalRequest: Identifiable, Sendable, Equatable {
    let id: String
    let call: AgentToolCall
    let reason: AgentToolPromptReason
    let preview: AgentToolApprovalPreview

    init(
        call: AgentToolCall,
        reason: AgentToolPromptReason,
        preview: AgentToolApprovalPreview
    ) {
        self.id = call.id
        self.call = call
        self.reason = reason
        self.preview = preview
    }
}

protocol AgentToolPreviewing {
    func preview(for call: AgentToolCall) async throws -> AgentToolApprovalPreview
}

enum AgentToolDenyReason: Sendable, Equatable {
    case missingCommand(toolID: String)
    case dangerousCommand(command: String)
    case previewUnavailable(toolID: String)
}

enum AgentToolPermissionDecision: Sendable, Equatable {
    case allow
    case prompt(AgentToolPromptReason)
    case deny(AgentToolDenyReason)
}

enum AgentCommandAllowRule: Sendable, Equatable {
    case exact(String)
    case prefix(String)

    func matches(_ command: String) -> Bool {
        let normalizedCommand = AgentShellCommandSafety.normalized(command)
        switch self {
        case .exact(let allowed):
            return normalizedCommand == AgentShellCommandSafety.normalized(allowed)
        case .prefix(let allowedPrefix):
            return normalizedCommand.hasPrefix(AgentShellCommandSafety.normalized(allowedPrefix))
        }
    }
}

/// Pure decision engine for Agent tool permissions.
///
/// This type does not execute tools and does not show UI. It only encodes the
/// default Phase F safety contract so UI and CLI callers can present the right
/// approval flow later.
struct AgentToolPermissionPolicy: Sendable, Equatable {
    let autoModeEnabled: Bool
    let commandAllowRules: [AgentCommandAllowRule]

    init(autoModeEnabled: Bool = false, commandAllowRules: [AgentCommandAllowRule] = []) {
        self.autoModeEnabled = autoModeEnabled
        self.commandAllowRules = commandAllowRules
    }

    func decision(for invocation: AgentToolInvocation) -> AgentToolPermissionDecision {
        switch invocation.capability {
        case .read:
            return .allow
        case .write:
            return .prompt(.diffPreviewRequired(toolID: invocation.toolID))
        case .command:
            return commandDecision(for: invocation)
        case .external:
            return .prompt(.externalToolApprovalRequired(toolID: invocation.toolID))
        case .userInteraction:
            return .prompt(.userInputRequired(toolID: invocation.toolID))
        }
    }

    private func commandDecision(for invocation: AgentToolInvocation) -> AgentToolPermissionDecision {
        guard let command = invocation.command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty
        else {
            return .deny(.missingCommand(toolID: invocation.toolID))
        }

        guard !AgentShellCommandSafety.isDangerous(command) else {
            return .deny(.dangerousCommand(command: command))
        }

        if commandAllowRules.contains(where: { $0.matches(command) }) {
            return .allow
        }

        return .prompt(.commandApprovalRequired(command: command))
    }
}

enum AgentShellCommandSafety {
    static func normalized(_ command: String) -> String {
        command
            .lowercased()
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isDangerous(_ command: String) -> Bool {
        let normalized = normalized(command)
        let compact = normalized.replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )

        if compact.contains(":(){:|:&};:") {
            return true
        }

        return dangerousPatterns.contains { pattern in
            normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static let dangerousPatterns: [String] = [
        #"(?:^|[;&|]\s*)(?:sudo\s+)?rm\s+-(?=[a-z-]*r)(?=[a-z-]*f)[a-z-]+\s+(?:--\s+)?/(?:\s|$)"#,
        #"(?:^|[;&|]\s*)(?:sudo\s+)?diskutil\s+erasedisk(?:\s|$)"#,
        #"(?:^|[;&|]\s*)(?:sudo\s+)?mkfs(?:\.[a-z0-9]+)?\s+/dev/"#,
        #"(?:^|[;&|]\s*)(?:sudo\s+)?dd\s+.*\bof=/dev/(?:disk|rdisk)"#,
        #"(?:^|[;&|]\s*)(?:sudo\s+)?chmod\s+-r\s+777\s+/(?:\s|$)"#,
    ]
}
