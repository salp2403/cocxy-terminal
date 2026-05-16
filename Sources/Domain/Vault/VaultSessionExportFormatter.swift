// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSessionExportFormatter.swift - Local export payloads for Vault sessions.

import Foundation

public enum VaultSessionExportFormat: String, CaseIterable, Sendable {
    case json
    case markdown
    case text
}

public enum VaultSessionExportFormatter {
    public static func data(
        for session: VaultSession,
        format: VaultSessionExportFormat
    ) throws -> Data {
        switch format {
        case .json:
            return try jsonData(for: session)
        case .markdown:
            return markdownData(for: session)
        case .text:
            return textData(for: session)
        }
    }

    public static func data(
        for sessions: [VaultSession],
        format: VaultSessionExportFormat
    ) throws -> Data {
        guard sessions.count != 1 else {
            if let first = sessions.first {
                return try data(for: first, format: format)
            }
            return Data()
        }

        switch format {
        case .json:
            let objects = sessions.map(jsonObject(for:))
            return try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
        case .markdown:
            let parts = sessions.map { session in
                String(decoding: markdownData(for: session), as: UTF8.self)
                    .trimmingCharacters(in: .newlines)
            }
            return Data((parts.joined(separator: "\n\n---\n\n") + "\n").utf8)
        case .text:
            let parts = sessions.map { session in
                String(decoding: textData(for: session), as: UTF8.self)
                    .trimmingCharacters(in: .newlines)
            }
            return Data((parts.joined(separator: "\n\n") + "\n").utf8)
        }
    }

    public static func suggestedFilename(
        for session: VaultSession,
        format: VaultSessionExportFormat
    ) -> String {
        let safeAgent = safeFilenameComponent(session.agentID.rawValue)
        let safeSession = safeFilenameComponent(session.sessionID)
        switch format {
        case .json:
            return "vault-\(safeAgent)-\(safeSession).json"
        case .markdown:
            return "vault-\(safeAgent)-\(safeSession).md"
        case .text:
            return "vault-\(safeAgent)-\(safeSession).txt"
        }
    }

    public static func suggestedFilename(
        for sessions: [VaultSession],
        format: VaultSessionExportFormat
    ) -> String {
        guard sessions.count != 1, let first = sessions.first else {
            return sessions.first.map { suggestedFilename(for: $0, format: format) } ?? "vault-export.txt"
        }
        let safeAgent = safeFilenameComponent(first.agentID.rawValue)
        let suffix: String
        switch format {
        case .json: suffix = "json"
        case .markdown: suffix = "md"
        case .text: suffix = "txt"
        }
        return "vault-\(safeAgent)-\(sessions.count)-sessions.\(suffix)"
    }

    public static func jsonObject(for session: VaultSession) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var object: [String: Any] = [
            "id": session.id,
            "agentID": session.agentID.rawValue,
            "agentDisplayName": session.agentDisplayName,
            "sessionID": session.sessionID,
            "capturedAt": formatter.string(from: session.capturedAt),
            "lastSeenAt": formatter.string(from: session.lastSeenAt),
            "source": session.source.rawValue,
            "sanitizedArguments": session.sanitizedArguments,
        ]
        object["workingDirectory"] = session.workingDirectory ?? NSNull()
        return object
    }

    private static func jsonData(for session: VaultSession) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: jsonObject(for: session),
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private static func markdownData(for session: VaultSession) -> Data {
        var lines = [
            "# Vault Session",
            "",
            "- Agent: \(session.agentDisplayName) (\(session.agentID.rawValue))",
            "- Session ID: \(session.sessionID)",
            "- Source: \(session.source.rawValue)",
            "- Captured: \(ISO8601DateFormatter().string(from: session.capturedAt))",
            "- Last Seen: \(ISO8601DateFormatter().string(from: session.lastSeenAt))",
        ]
        if let workingDirectory = session.workingDirectory, !workingDirectory.isEmpty {
            lines.append("- Workspace: \(workingDirectory)")
        }
        if !session.sanitizedArguments.isEmpty {
            lines.append("")
            lines.append("## Sanitized Arguments")
            lines.append("")
            lines.append("```text")
            lines.append(session.sanitizedArguments.joined(separator: " "))
            lines.append("```")
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func textData(for session: VaultSession) -> Data {
        var lines = [
            "Vault Session",
            "Agent: \(session.agentDisplayName) (\(session.agentID.rawValue))",
            "Session ID: \(session.sessionID)",
            "Source: \(session.source.rawValue)",
            "Captured: \(ISO8601DateFormatter().string(from: session.capturedAt))",
            "Last Seen: \(ISO8601DateFormatter().string(from: session.lastSeenAt))",
        ]
        if let workingDirectory = session.workingDirectory, !workingDirectory.isEmpty {
            lines.append("Workspace: \(workingDirectory)")
        }
        if !session.sanitizedArguments.isEmpty {
            lines.append("Arguments: \(session.sanitizedArguments.joined(separator: " "))")
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func safeFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "session" : result
    }
}
