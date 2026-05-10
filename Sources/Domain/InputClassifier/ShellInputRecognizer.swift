// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

enum ShellInputRecognizer {
    static let commonCommands: Set<String> = [
        "awk", "brew", "cat", "cd", "chmod", "chown", "clear", "cp", "curl",
        "docker", "echo", "env", "find", "gh", "git", "grep", "head", "kill",
        "less", "ln", "ls", "make", "mkdir", "mv", "open", "osascript", "perl",
        "php", "ps", "pwd", "python", "python3", "rg", "rm", "rsync", "ruby",
        "sed", "sh", "sleep", "ssh", "sudo", "swift", "tail", "tar", "touch",
        "vim", "which", "xcodebuild", "xcrun", "zsh"
    ]

    private static let shellOperators = ["&&", "||", "|", ";", ">", "<", ">>", "$(", "`"]

    static func normalized(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
    }

    static func looksLikeShellCommand(_ input: String) -> Bool {
        let normalizedInput = normalized(input)
        guard !normalizedInput.isEmpty else { return false }

        if shellOperators.contains(where: normalizedInput.contains) {
            return true
        }

        guard let firstToken = normalizedInput.split(separator: " ").first else {
            return false
        }
        let command = String(firstToken)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased()

        if command.hasPrefix("./") || command.hasPrefix("/") || command.hasPrefix("~/") {
            return true
        }

        return commonCommands.contains(command)
    }

    static func firstToken(in input: String) -> String? {
        normalized(input)
            .split(separator: " ")
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased()
    }
}
