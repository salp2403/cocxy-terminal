// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AliasManager.swift - Shell alias rendering without mutating user startup files.

import Foundation

enum ShellKind: String, Codable, CaseIterable, Equatable, Sendable {
    case zsh
    case bash
    case fish
}

enum AliasManagerError: Error, Equatable, Sendable {
    case invalidName(String)
    case unsafeValue(String)
}

struct AliasManager: Sendable {
    func validate(_ alias: ShellAlias) throws {
        guard alias.name.range(
            of: #"^[A-Za-z_][A-Za-z0-9_-]*$"#,
            options: .regularExpression
        ) != nil else {
            throw AliasManagerError.invalidName(alias.name)
        }
        guard !alias.value.contains("\0"),
              !alias.value.contains("\n") else {
            throw AliasManagerError.unsafeValue(alias.value)
        }
    }

    func renderBlock(
        aliases: [ShellAlias],
        shell: ShellKind
    ) throws -> String {
        let sortedAliases = aliases.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        var lines = [
            "# Cocxy aliases begin",
        ]
        for alias in sortedAliases {
            try validate(alias)
            lines.append(render(alias, shell: shell))
        }
        lines.append("# Cocxy aliases end")
        return lines.joined(separator: "\n") + "\n"
    }

    private func render(_ alias: ShellAlias, shell: ShellKind) -> String {
        switch shell {
        case .zsh, .bash:
            return "alias \(alias.name)=\(singleQuoted(alias.value))"
        case .fish:
            return "alias \(alias.name) \(singleQuoted(alias.value))"
        }
    }

    private func singleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
