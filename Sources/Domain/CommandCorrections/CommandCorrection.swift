// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public enum CommandCorrectionSource: String, Codable, Sendable, Equatable, CaseIterable {
    case commonTypo = "common-typo"
    case editDistance = "edit-distance"
    case shellHint = "shell-hint"
    case pathHeuristic = "path-heuristic"
    case foundationModels = "foundation-models"
    case agent = "agent"
}

public struct CommandCorrection: Codable, Sendable, Equatable, Identifiable {
    public let original: String
    public let suggestion: String
    public let reason: String
    public let confidence: Double
    public let source: CommandCorrectionSource

    public var id: String {
        "\(source.rawValue):\(suggestion)"
    }

    public init(
        original: String,
        suggestion: String,
        reason: String,
        confidence: Double,
        source: CommandCorrectionSource
    ) {
        self.original = original
        self.suggestion = suggestion
        self.reason = reason
        self.confidence = min(max(confidence, 0), 1)
        self.source = source
    }
}

public struct CommandCorrectionContext: Sendable, Equatable {
    public let command: String
    public let exitCode: Int32?
    public let stdout: String
    public let stderr: String
    public let workingDirectory: URL?

    public init(
        command: String,
        exitCode: Int32? = nil,
        stdout: String = "",
        stderr: String = "",
        workingDirectory: URL? = nil
    ) {
        self.command = command
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.workingDirectory = workingDirectory
    }

    public var normalizedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct CommandExecutionSnapshot: Sendable, Equatable {
    public let command: String
    public let exitCode: Int32?
    public let stdout: String
    public let stderr: String
    public let workingDirectory: URL?

    public init(
        command: String,
        exitCode: Int32?,
        stdout: String = "",
        stderr: String = "",
        workingDirectory: URL? = nil
    ) {
        self.command = command
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.workingDirectory = workingDirectory
    }

    public var failed: Bool {
        guard let exitCode else { return false }
        return exitCode != 0
    }

    public var context: CommandCorrectionContext {
        CommandCorrectionContext(
            command: command,
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
            workingDirectory: workingDirectory
        )
    }
}

public protocol CommandCorrectionProvider: Sendable {
    func corrections(for context: CommandCorrectionContext) -> [CommandCorrection]
}

enum CommandCorrectionCommandLine {
    struct Split: Equatable {
        let firstToken: String
        let suffix: String
    }

    static func splitFirstToken(_ command: String) -> Split? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var token = ""
        var index = trimmed.startIndex
        var quote: Character?
        var escaped = false

        while index < trimmed.endIndex {
            let character = trimmed[index]
            if escaped {
                token.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
                token.append(character)
            } else if let activeQuote = quote {
                token.append(character)
                if character == activeQuote {
                    quote = nil
                }
            } else if character == "'" || character == "\"" {
                quote = character
                token.append(character)
            } else if character.isWhitespace {
                break
            } else {
                token.append(character)
            }
            index = trimmed.index(after: index)
        }

        let suffix = index < trimmed.endIndex ? String(trimmed[index...]) : ""
        let unquoted = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return Split(firstToken: unquoted, suffix: suffix)
    }

    static func replacingFirstToken(in command: String, with replacement: String) -> String {
        guard let split = splitFirstToken(command) else { return replacement }
        return replacement + split.suffix
    }

    static func shellEscapedPath(_ path: String) -> String {
        guard path.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
                || path.contains("'")
        else {
            return path
        }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            for rightIndex in 1...right.count {
                if left[leftIndex - 1] == right[rightIndex - 1] {
                    current[rightIndex] = previous[rightIndex - 1]
                } else {
                    current[rightIndex] = min(
                        previous[rightIndex],
                        current[rightIndex - 1],
                        previous[rightIndex - 1]
                    ) + 1
                }
            }
            previous = current
        }

        return previous[right.count]
    }
}
