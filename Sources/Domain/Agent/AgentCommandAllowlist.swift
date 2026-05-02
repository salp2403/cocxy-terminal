// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentCommandAllowlist.swift - User-controlled local command approval rules.

import Foundation

protocol AgentCommandAllowlistLoading: Sendable {
    func loadRules() throws -> [AgentCommandAllowRule]
}

protocol AgentCommandAllowlistFileProviding: Sendable {
    func readCommandAllowlistFile() throws -> String?
}

struct AgentCommandAllowlist: AgentCommandAllowlistLoading {
    let fileProvider: any AgentCommandAllowlistFileProviding

    init(fileProvider: any AgentCommandAllowlistFileProviding = FileAgentCommandAllowlistFileProvider()) {
        self.fileProvider = fileProvider
    }

    func loadRules() throws -> [AgentCommandAllowRule] {
        guard let content = try fileProvider.readCommandAllowlistFile() else {
            return []
        }
        return Self.parse(content)
    }

    static func parse(_ content: String) -> [AgentCommandAllowRule] {
        var rules: [AgentCommandAllowRule] = []
        var seen: Set<String> = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = stripComment(from: rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let equalsIndex = line.firstIndex(of: "=") else { continue }

            let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == "exact" || key == "prefix" else { continue }

            let rawValue = line[line.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard rawValue.hasPrefix("["),
                  rawValue.hasSuffix("]")
            else {
                continue
            }

            for command in parseStringArray(rawValue) {
                let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }

                let marker = "\(key):\(normalized)"
                guard seen.insert(marker).inserted else { continue }

                if key == "exact" {
                    rules.append(.exact(normalized))
                } else {
                    rules.append(.prefix(normalized))
                }
            }
        }

        return rules
    }

    private static func stripComment(from line: String) -> String {
        var result = ""
        var isInsideString = false
        var isEscaped = false

        for character in line {
            if isEscaped {
                result.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" && isInsideString {
                result.append(character)
                isEscaped = true
                continue
            }
            if character == "\"" {
                isInsideString.toggle()
                result.append(character)
                continue
            }
            if character == "#", !isInsideString {
                break
            }
            result.append(character)
        }

        return result
    }

    private static func parseStringArray(_ rawValue: String) -> [String] {
        let body = rawValue.dropFirst().dropLast()
        var values: [String] = []
        var current = ""
        var isInsideString = false
        var isEscaped = false

        for character in body {
            if !isInsideString {
                if character == "\"" {
                    isInsideString = true
                    current = ""
                }
                continue
            }

            if isEscaped {
                switch character {
                case "n":
                    current.append("\n")
                case "t":
                    current.append("\t")
                case "\"", "\\":
                    current.append(character)
                default:
                    current.append(character)
                }
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "\"" {
                values.append(current)
                current = ""
                isInsideString = false
                continue
            }

            current.append(character)
        }

        return values
    }
}

struct FileAgentCommandAllowlistFileProvider: AgentCommandAllowlistFileProviding {
    let fileURL: URL

    init(fileURL: URL = FileAgentCommandAllowlistFileProvider.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func readCommandAllowlistFile() throws -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/agent/auto-allow.toml")
    }
}
