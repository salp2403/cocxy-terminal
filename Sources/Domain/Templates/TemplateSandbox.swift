// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TemplateSandbox.swift - Conservative validation for local scaffold hooks.

import Foundation

struct ProjectTemplateHookCommand: Sendable, Equatable {
    let executable: String
    let arguments: [String]
}

struct ProjectTemplateHookSandbox: Sendable, Equatable {
    let allowedExecutables: Set<String>
    let blockedExecutables: Set<String>

    init(
        allowedExecutables: Set<String> = Self.defaultAllowedExecutables,
        blockedExecutables: Set<String> = Self.defaultBlockedExecutables
    ) {
        self.allowedExecutables = allowedExecutables
        self.blockedExecutables = blockedExecutables
    }

    func validate(_ command: String) throws -> ProjectTemplateHookCommand {
        let parsed = try Self.parse(command)
        guard !parsed.executable.contains("/") else {
            throw ProjectTemplateHookError.executablePathNotAllowed(parsed.executable)
        }
        if blockedExecutables.contains(parsed.executable) {
            throw ProjectTemplateHookError.executableBlocked(parsed.executable)
        }
        guard allowedExecutables.contains(parsed.executable) else {
            throw ProjectTemplateHookError.executableNotAllowed(parsed.executable)
        }

        for argument in parsed.arguments where Self.isUnsafeArgument(argument) {
            throw ProjectTemplateHookError.unsafeArgument(argument)
        }
        try validateSubcommand(parsed)
        return parsed
    }

    static func parse(_ command: String) throws -> ProjectTemplateHookCommand {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProjectTemplateHookError.emptyCommand
        }

        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        for character in trimmed {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            if Self.shellOperators.contains(character) {
                throw ProjectTemplateHookError.shellOperatorNotAllowed(command)
            }

            current.append(character)
        }

        if let _ = quote {
            throw ProjectTemplateHookError.unterminatedQuote(command)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        guard let executable = tokens.first else {
            throw ProjectTemplateHookError.emptyCommand
        }

        return ProjectTemplateHookCommand(
            executable: executable,
            arguments: Array(tokens.dropFirst())
        )
    }

    private func validateSubcommand(_ command: ProjectTemplateHookCommand) throws {
        switch command.executable {
        case "git":
            try requireAllowedSubcommand(
                command,
                allowed: ["add", "branch", "checkout", "commit", "config", "init", "restore", "status", "switch"]
            )
        case "swift":
            try requireAllowedSubcommand(command, allowed: ["build", "package", "test"])
        case "cargo":
            try requireAllowedSubcommand(command, allowed: ["check", "fmt", "test"])
        case "go":
            try requireAllowedSubcommand(command, allowed: ["fmt", "test"])
        case "npm":
            try requireAllowedSubcommand(command, allowed: ["run", "test"])
        case "python", "python3":
            try validatePython(command)
        case "ruby":
            try requireAllowedSubcommand(command, allowed: ["-c"])
        case "php":
            try requireAllowedSubcommand(command, allowed: ["-l"])
        case "dart", "flutter":
            try requireAllowedSubcommand(command, allowed: ["analyze", "test"])
        default:
            break
        }
    }

    private func requireAllowedSubcommand(
        _ command: ProjectTemplateHookCommand,
        allowed: Set<String>
    ) throws {
        guard let subcommand = command.arguments.first else { return }
        guard allowed.contains(subcommand) else {
            throw ProjectTemplateHookError.subcommandNotAllowed(
                executable: command.executable,
                subcommand: subcommand
            )
        }
    }

    private func validatePython(_ command: ProjectTemplateHookCommand) throws {
        guard !command.arguments.isEmpty else { return }
        if command.arguments.first == "-m" {
            let module = command.arguments.dropFirst().first ?? ""
            guard ["unittest"].contains(module) else {
                throw ProjectTemplateHookError.subcommandNotAllowed(
                    executable: command.executable,
                    subcommand: "-m \(module)"
                )
            }
            return
        }
        throw ProjectTemplateHookError.subcommandNotAllowed(
            executable: command.executable,
            subcommand: command.arguments.first ?? ""
        )
    }

    private static func isUnsafeArgument(_ argument: String) -> Bool {
        if argument.isEmpty || argument.hasPrefix("/") || argument.hasPrefix("~") {
            return true
        }
        if argument.contains("\0") || argument.contains("`") || argument.contains("$(") {
            return true
        }
        return argument
            .split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0 == ".." }
    }

    private static let shellOperators = Set<Character>([";", "|", "&", "<", ">"])

    private static let defaultAllowedExecutables: Set<String> = [
        "cargo",
        "dart",
        "echo",
        "flutter",
        "git",
        "go",
        "mkdir",
        "npm",
        "php",
        "python",
        "python3",
        "ruby",
        "swift",
        "touch",
        "true",
    ]

    private static let defaultBlockedExecutables: Set<String> = [
        "curl",
        "nc",
        "rm",
        "rsync",
        "scp",
        "ssh",
        "sudo",
        "wget",
    ]
}
