// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitAssistantSocketAuthority.swift - Exact authority binding for socket generation requests.

import Foundation

enum GitAssistantSocketAuthority {
    static let automaticRevision = "(automatic)"

    static func details(
        request: SocketPrivilegedCommandAuthorizationRequest,
        provider: AgentProviderKind,
        workingDirectory: URL
    ) -> [String: String]? {
        guard let kind = kind(for: request.command) else { return nil }
        return details(
            kind: kind,
            params: request.params,
            provider: provider,
            workingDirectory: workingDirectory
        )
    }

    static func matches(
        kind: String,
        params: [String: String],
        provider: AgentProviderKind,
        workingDirectory: URL,
        context: SocketPrivilegedCommandContext
    ) -> Bool {
        guard context.scope == .repository,
              context.workingDirectory == workingDirectory.standardizedFileURL.path,
              let expected = details(
                kind: kind,
                params: params,
                provider: provider,
                workingDirectory: workingDirectory
              ) else {
            return false
        }
        return context.authorityDetails == expected
    }

    static func kind(for command: CLICommandName) -> String? {
        switch command {
        case .gitAssistantCommitMessage: return "commit-message"
        case .gitAssistantPRDraft: return "pr-draft"
        case .gitAssistantReleaseNotes: return "release-notes"
        default: return nil
        }
    }

    private static func details(
        kind: String,
        params: [String: String],
        provider: AgentProviderKind,
        workingDirectory: URL
    ) -> [String: String]? {
        var details = [
            "operation": kind,
            "provider": provider.rawValue,
            "repository": workingDirectory.standardizedFileURL.path,
        ]
        switch kind {
        case "commit-message":
            guard params.isEmpty else { return nil }
        case "pr-draft", "release-notes":
            guard Set(params.keys).isSubset(of: Set(["base", "head"])) else { return nil }
            guard let base = normalizedRevision(params["base"]),
                  let head = normalizedRevision(params["head"]) else {
                return nil
            }
            details["base"] = base
            details["head"] = head
        default:
            return nil
        }
        return details
    }

    private static func normalizedRevision(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return automaticRevision
        }
        guard (try? GitRevisionArgument(value)) != nil else { return nil }
        return value
    }
}
