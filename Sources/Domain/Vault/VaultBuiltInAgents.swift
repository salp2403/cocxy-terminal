// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultBuiltInAgents.swift - Built-in external agent registry.

import Foundation

public enum VaultBuiltInAgents {
    public static let all: [VaultAgent] = [
        VaultAgent(
            id: "claude",
            displayName: "Claude",
            binaryNames: ["claude"],
            resumeArgumentsTemplate: ["--resume", "{{sessionID}}"]
        ),
        VaultAgent(
            id: "codex",
            displayName: "Codex",
            binaryNames: ["codex"],
            resumeArgumentsTemplate: ["resume", "{{sessionID}}"]
        ),
        VaultAgent(
            id: "opencode",
            displayName: "OpenCode",
            binaryNames: ["opencode", "open-code"],
            resumeArgumentsTemplate: ["resume", "{{sessionID}}"]
        ),
        VaultAgent(
            id: "pi",
            displayName: "Pi",
            binaryNames: ["pi"],
            resumeArgumentsTemplate: ["resume", "{{sessionID}}"]
        ),
        VaultAgent(
            id: "cursor",
            displayName: "Cursor",
            binaryNames: ["cursor-agent", "cursor"],
            resumeArgumentsTemplate: ["resume", "{{sessionID}}"]
        ),
        VaultAgent(
            id: "gemini",
            displayName: "Gemini",
            binaryNames: ["gemini"],
            resumeArgumentsTemplate: ["resume", "{{sessionID}}"]
        ),
        VaultAgent(
            id: "rovo",
            displayName: "Rovo",
            binaryNames: ["rovo"],
            resumeArgumentsTemplate: ["resume", "{{sessionID}}"]
        ),
        VaultAgent(
            id: "copilot",
            displayName: "Copilot",
            binaryNames: ["copilot"],
            resumeArgumentsTemplate: ["resume", "{{sessionID}}"]
        ),
        VaultAgent(
            id: "codebuddy",
            displayName: "CodeBuddy",
            binaryNames: ["codebuddy"],
            resumeArgumentsTemplate: ["resume", "{{sessionID}}"]
        ),
        VaultAgent(
            id: "factory",
            displayName: "Factory",
            binaryNames: ["factory"],
            resumeArgumentsTemplate: ["resume", "{{sessionID}}"]
        ),
        VaultAgent(
            id: "qoder",
            displayName: "Qoder",
            binaryNames: ["qoder"],
            resumeArgumentsTemplate: ["resume", "{{sessionID}}"]
        ),
    ]
}

public struct VaultAgentRegistry: Sendable {
    public let agents: [VaultAgent]

    public static let builtIn = VaultAgentRegistry(agents: VaultBuiltInAgents.all)

    public init(agents: [VaultAgent]) {
        var seen = Set<VaultAgentID>()
        self.agents = agents.filter { agent in
            seen.insert(agent.id).inserted
        }
    }

    public func agent(matching value: String) -> VaultAgent? {
        let normalized = Self.normalize(value)
        return agents.first { agent in
            agent.id.rawValue == normalized
                || Self.normalize(agent.displayName) == normalized
                || agent.binaryNames.contains { Self.normalize($0) == normalized }
        }
    }

    private static func normalize(_ value: String) -> String {
        URL(fileURLWithPath: value).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}
