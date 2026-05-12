// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentSource.swift - Identifies which external agent emitted a hook event.

import Foundation

enum AgentSource: String, CaseIterable, Sendable {
    case claudeCode
    case codex
    case geminiCLI
    case kiro
    case opencode
    case pi
    case cursor
    case rovoDev = "rovo-dev"
    case copilot
    case codebuddy
    case factory
    case qoder
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
        case .opencode:
            return "OpenCode"
        case .pi:
            return "Pi"
        case .cursor:
            return "Cursor"
        case .rovoDev:
            return "Rovo Dev"
        case .copilot:
            return "Copilot"
        case .codebuddy:
            return "CodeBuddy"
        case .factory:
            return "Factory"
        case .qoder:
            return "Qoder"
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
        case .opencode:
            return "opencode"
        case .pi:
            return "pi"
        case .cursor:
            return "cursor"
        case .rovoDev:
            return "rovo-dev"
        case .copilot:
            return "copilot"
        case .codebuddy:
            return "codebuddy"
        case .factory:
            return "factory"
        case .qoder:
            return "qoder"
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
        case .opencode:
            return "opencode"
        case .pi:
            return "pi"
        case .cursor:
            return "cursor"
        case .rovoDev:
            return "rovo"
        case .copilot:
            return "copilot"
        case .codebuddy:
            return "codebuddy"
        case .factory:
            return "factory"
        case .qoder:
            return "qoder"
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
        case .opencode:
            return ["opencode", "open-code"]
        case .pi:
            return ["pi"]
        case .cursor:
            return ["cursor-agent", "cursor"]
        case .rovoDev:
            return ["acli", "rovodev", "rovo"]
        case .copilot:
            return ["copilot"]
        case .codebuddy:
            return ["codebuddy"]
        case .factory:
            return ["droid", "factory"]
        case .qoder:
            return ["qodercli", "qoder"]
        case .unknown:
            return []
        }
    }

    var supportsAutomaticHookSetup: Bool {
        switch self {
        case .claudeCode, .codex, .geminiCLI, .cursor, .copilot, .codebuddy, .factory, .qoder:
            return true
        case .kiro, .opencode, .pi, .rovoDev, .unknown:
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
        case .cursor:
            return "\(home)/.cursor/hooks.json"
        case .copilot:
            return "\(home)/.copilot/config.json"
        case .codebuddy:
            return "\(home)/.codebuddy/settings.json"
        case .factory:
            return "\(home)/.factory/settings.json"
        case .qoder:
            return "\(home)/.qoder/settings.json"
        case .kiro, .opencode, .pi, .rovoDev, .unknown:
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
        case .cursor, .copilot, .codebuddy, .factory, .qoder:
            return ["SessionStart", "SessionEnd", "PreToolUse", "PostToolUse", "Stop", "UserPromptSubmit"]
        case .opencode, .pi, .rovoDev, .unknown:
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
        case "opencode":
            return .opencode
        case "pi":
            return .pi
        case "cursor":
            return .cursor
        case "rovo", "rovo-dev", "rovodev":
            return .rovoDev
        case "copilot":
            return .copilot
        case "codebuddy":
            return .codebuddy
        case "factory":
            return .factory
        case "qoder":
            return .qoder
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
        if environment["OPENCODE_SESSION_ID"] != nil {
            return .opencode
        }
        if environment["PI_SESSION_ID"] != nil {
            return .pi
        }
        if environment["CURSOR_SESSION_ID"] != nil {
            return .cursor
        }
        if environment["ROVO_SESSION_ID"] != nil || environment["ROVODEV_SESSION_ID"] != nil {
            return .rovoDev
        }
        if environment["COPILOT_SESSION_ID"] != nil {
            return .copilot
        }
        if environment["CODEBUDDY_SESSION_ID"] != nil {
            return .codebuddy
        }
        if environment["FACTORY_SESSION_ID"] != nil {
            return .factory
        }
        if environment["QODER_SESSION_ID"] != nil {
            return .qoder
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
        let keys = [
            "CLAUDE_SESSION_ID",
            "CODEX_THREAD_ID",
            "GEMINI_SESSION_ID",
            "KIRO_SESSION_ID",
            "OPENCODE_SESSION_ID",
            "PI_SESSION_ID",
            "CURSOR_SESSION_ID",
            "ROVO_SESSION_ID",
            "ROVODEV_SESSION_ID",
            "COPILOT_SESSION_ID",
            "CODEBUDDY_SESSION_ID",
            "FACTORY_SESSION_ID",
            "QODER_SESSION_ID"
        ]
        return keys.lazy.compactMap { environment[$0] }.first
    }
}
