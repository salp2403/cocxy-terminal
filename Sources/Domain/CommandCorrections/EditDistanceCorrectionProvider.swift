// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public struct EditDistanceCorrectionProvider: CommandCorrectionProvider {
    public let threshold: Int
    public let commands: [String]

    public init(
        threshold: Int = 2,
        commands: [String] = Self.defaultCommands
    ) {
        self.threshold = max(1, threshold)
        self.commands = commands
    }

    public func corrections(for context: CommandCorrectionContext) -> [CommandCorrection] {
        guard let split = CommandCorrectionCommandLine.splitFirstToken(context.command),
              split.firstToken.count >= 2,
              !split.firstToken.contains("/")
        else {
            return []
        }

        let token = split.firstToken.lowercased()
        guard !commands.contains(token) else { return [] }
        return commands
            .filter { $0 != token && abs($0.count - token.count) <= threshold }
            .compactMap { command -> (String, Int)? in
                let distance = CommandCorrectionCommandLine.editDistance(token, command)
                guard distance <= threshold else { return nil }
                return (command, distance)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0 < rhs.0
            }
            .prefix(3)
            .map { candidate, distance in
                let confidence = max(0.62, 0.92 - Double(distance - 1) * 0.14)
                return CommandCorrection(
                    original: context.normalizedCommand,
                    suggestion: CommandCorrectionCommandLine.replacingFirstToken(
                        in: context.command,
                        with: candidate
                    ),
                    reason: "Nearest installed command name by edit distance",
                    confidence: confidence,
                    source: .editDistance
                )
            }
    }

    public static let defaultCommands = [
        "ack", "awk", "bash", "bat", "brew", "bundle", "bun", "cargo",
        "cat", "cd", "chmod", "chown", "clear", "cp", "curl", "docker", "find",
        "fish", "gh", "git", "grep", "head", "jq", "kill", "kubectl",
        "less", "ls", "make", "mkdir", "more", "mv", "node", "npm",
        "open", "perl", "php", "pnpm", "python", "python3", "rg", "rm",
        "rsync", "ruby", "sed", "ssh", "sudo", "swift", "tail", "tar",
        "touch", "tree", "vim", "wget", "yarn", "zig", "zsh"
    ]
}
