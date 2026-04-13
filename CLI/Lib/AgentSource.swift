// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentSource.swift - Identifies which external agent emitted a hook event.

import Foundation

enum AgentSource: String, CaseIterable, Sendable {
    case claudeCode
    case codex
    case geminiCLI
    case kiro
    case unknown

    var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex CLI"
        case .geminiCLI:
            return "Gemini CLI"
        case .kiro:
            return "Kiro"
        case .unknown:
            return "Unknown"
        }
    }

    var configAgentName: String? {
        switch self {
        case .claudeCode:
            return "claude"
        case .codex:
            return "codex"
        case .geminiCLI:
            return "gemini-cli"
        case .kiro:
            return "kiro"
        case .unknown:
            return nil
        }
    }

    var cliArgumentName: String {
        switch self {
        case .claudeCode:
            return "claude"
        case .codex:
            return "codex"
        case .geminiCLI:
            return "gemini"
        case .kiro:
            return "kiro"
        case .unknown:
            return "unknown"
        }
    }

    var executableCandidates: [String] {
        switch self {
        case .claudeCode:
            return ["claude", "claude-code"]
        case .codex:
            return ["codex"]
        case .geminiCLI:
            return ["gemini"]
        case .kiro:
            return ["kiro", "kiro-cli"]
        case .unknown:
            return []
        }
    }

    var supportsAutomaticHookSetup: Bool {
        switch self {
        case .claudeCode, .codex, .geminiCLI:
            return true
        case .kiro, .unknown:
            return false
        }
    }

    var hookSettingsFilePath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .claudeCode:
            return "\(home)/.claude/settings.json"
        case .codex:
            return "\(home)/.codex/hooks.json"
        case .geminiCLI:
            return "\(home)/.gemini/settings.json"
        case .kiro, .unknown:
            return nil
        }
    }

    var hookEventNames: [String] {
        switch self {
        case .claudeCode:
            return ClaudeSettingsManager.hookedEventTypes
        case .codex:
            return ["PreToolUse", "PostToolUse", "SessionStart", "Stop", "UserPromptSubmit"]
        case .geminiCLI:
            return ["BeforeTool", "AfterTool", "SessionStart", "SessionEnd"]
        case .kiro:
            return ["agentSpawn", "userPromptSubmit", "preToolUse", "postToolUse", "stop"]
        case .unknown:
            return []
        }
    }

    static func fromCLIArgument(_ rawValue: String) -> AgentSource? {
        switch rawValue.lowercased() {
        case "claude":
            return .claudeCode
        case "codex":
            return .codex
        case "gemini":
            return .geminiCLI
        case "kiro":
            return .kiro
        default:
            return nil
        }
    }

    static func detect(
        environment: [String: String],
        payload: [String: Any]? = nil
    ) -> AgentSource {
        if let forcedSource = environment["COCXY_HOOK_AGENT"],
           let source = fromCLIArgument(forcedSource) {
            return source
        }

        if environment["CLAUDE_SESSION_ID"] != nil {
            return .claudeCode
        }
        if environment["CODEX_THREAD_ID"] != nil {
            return .codex
        }
        if environment["GEMINI_SESSION_ID"] != nil {
            return .geminiCLI
        }
        if environment["KIRO_SESSION_ID"] != nil {
            return .kiro
        }

        guard let rawEventName = payload?["hook_event_name"] as? String else {
            return .unknown
        }

        switch rawEventName {
        case "BeforeTool", "AfterTool", "SessionEnd":
            return .geminiCLI
        case "preToolUse", "postToolUse", "agentSpawn", "stop", "userPromptSubmit":
            return .kiro
        default:
            return .unknown
        }
    }

    static func resolveSessionID(from environment: [String: String]) -> String? {
        environment["CLAUDE_SESSION_ID"]
            ?? environment["CODEX_THREAD_ID"]
            ?? environment["GEMINI_SESSION_ID"]
            ?? environment["KIRO_SESSION_ID"]
    }
}
