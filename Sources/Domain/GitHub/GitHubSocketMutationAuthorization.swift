// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubSocketMutationAuthorization.swift - Context-bound grants for local socket mutations.

import CryptoKit
import Foundation

enum GitHubSocketMutationSource: String, Equatable, Sendable {
    case localSocket
}

struct GitHubRepositoryAuthority: Equatable, Sendable {
    let host: String
    let ownerLogin: String
    let name: String

    init?(repository: GitHubRepo) {
        guard let host = repository.url.host else { return nil }
        let authorityHost: String
        if let port = repository.url.port,
           !((repository.url.scheme == "https" && port == 443)
             || (repository.url.scheme == "http" && port == 80)) {
            authorityHost = "\(host):\(port)"
        } else {
            authorityHost = host
        }
        self.init(
            host: authorityHost,
            ownerLogin: repository.owner.login,
            name: repository.name
        )
    }

    init?(host rawHost: String, ownerLogin rawOwner: String, name rawName: String) {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let owner = rawOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty,
              !owner.isEmpty,
              !name.isEmpty,
              !host.contains("/"),
              !owner.contains("/"),
              !name.contains("/") else {
            return nil
        }
        self.host = host
        ownerLogin = owner
        self.name = name
    }

    var displayName: String {
        host == "github.com"
            ? "\(ownerLogin)/\(name)"
            : "\(host)/\(ownerLogin)/\(name)"
    }

    var ghSelector: String { "\(host)/\(ownerLogin)/\(name)" }

    func matches(_ repository: GitHubRepo) -> Bool {
        guard let candidate = GitHubRepositoryAuthority(repository: repository) else {
            return false
        }
        return host.caseInsensitiveCompare(candidate.host) == .orderedSame
            && ownerLogin.caseInsensitiveCompare(candidate.ownerLogin) == .orderedSame
            && name.caseInsensitiveCompare(candidate.name) == .orderedSame
    }

    func matches(ownerLogin candidateOwner: String, name candidateName: String) -> Bool {
        ownerLogin.caseInsensitiveCompare(
            candidateOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        ) == .orderedSame
            && name.caseInsensitiveCompare(
                candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
            ) == .orderedSame
    }
}

struct GitHubSocketMutationContext: Equatable, Sendable {
    let windowControllerIdentifier: ObjectIdentifier
    let tabID: TabID
    let workingDirectory: String
    let repository: GitHubRepositoryAuthority

    init(
        windowControllerIdentifier: ObjectIdentifier,
        tabID: TabID,
        workingDirectory: URL,
        repository: GitHubRepositoryAuthority
    ) {
        self.windowControllerIdentifier = windowControllerIdentifier
        self.tabID = tabID
        self.workingDirectory = workingDirectory.standardizedFileURL.path
        self.repository = repository
    }
}

enum GitHubSocketMutationIntent: Equatable, Sendable {
    case merge(GitHubMergeRequest)
    case review(
        pullRequestNumber: Int,
        action: GitHubPullRequestReviewAction,
        body: String?
    )

    var pullRequestNumber: Int {
        switch self {
        case .merge(let request): return request.pullRequestNumber
        case .review(let number, _, _): return number
        }
    }
}

struct GitHubSocketMutationAuthorizationRequest: Equatable, Sendable {
    static let authorizationLifetime: TimeInterval = 60

    let id: UUID
    let source: GitHubSocketMutationSource
    let intent: GitHubSocketMutationIntent
    let context: GitHubSocketMutationContext
    let authorizationDigest: String
    let createdAt: Date
    let expiresAt: Date

    init(
        id: UUID = UUID(),
        source: GitHubSocketMutationSource = .localSocket,
        intent: GitHubSocketMutationIntent,
        context: GitHubSocketMutationContext,
        createdAt: Date = Date(),
        lifetime: TimeInterval = authorizationLifetime
    ) {
        self.id = id
        self.source = source
        self.intent = intent
        self.context = context
        self.createdAt = createdAt
        expiresAt = createdAt.addingTimeInterval(lifetime)
        authorizationDigest = GitHubSocketMutationSecurity.digest(
            source: source,
            intent: intent,
            context: context
        )
    }

    func isValid(at date: Date) -> Bool {
        source == .localSocket
            && intent.pullRequestNumber > 0
            && expiresAt > createdAt
            && date >= createdAt
            && date < expiresAt
            && authorizationDigest == GitHubSocketMutationSecurity.digest(
                source: source,
                intent: intent,
                context: context
            )
    }
}

struct GitHubSocketMutationAuthorizationGrant: Equatable, Sendable {
    let request: GitHubSocketMutationAuthorizationRequest
    let approvedAt: Date

    init?(request: GitHubSocketMutationAuthorizationRequest, approvedAt: Date = Date()) {
        guard request.isValid(at: approvedAt) else { return nil }
        self.request = request
        self.approvedAt = approvedAt
    }

    func isValid(for directory: URL, at date: Date) -> Bool {
        approvedAt >= request.createdAt
            && approvedAt < request.expiresAt
            && date >= approvedAt
            && request.isValid(at: date)
            && directory.standardizedFileURL.path == request.context.workingDirectory
    }
}

enum GitHubSocketMutationAuthorizationError: Error, Equatable, LocalizedError {
    case invalidOrExpired
    case alreadyConsumed
    case repositoryChanged

    var errorDescription: String? {
        switch self {
        case .invalidOrExpired:
            return "The GitHub approval is invalid, expired, or no longer matches the active tab."
        case .alreadyConsumed:
            return "The GitHub approval has already been used."
        case .repositoryChanged:
            return "The active repository changed after approval; no GitHub action was performed."
        }
    }
}

enum GitHubSocketMutationSecurity {
    static func normalizedText(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static func digest(
        source: GitHubSocketMutationSource,
        intent: GitHubSocketMutationIntent,
        context: GitHubSocketMutationContext
    ) -> String {
        var components = [
            source.rawValue,
            context.repository.host,
            context.repository.ownerLogin.lowercased(),
            context.repository.name.lowercased(),
            String(describing: context.windowControllerIdentifier),
            context.tabID.rawValue.uuidString.lowercased(),
            context.workingDirectory,
        ]
        switch intent {
        case .merge(let request):
            components.append(contentsOf: [
                "merge",
                String(request.pullRequestNumber),
                request.method.rawValue,
                request.deleteBranch ? "true" : "false",
                request.subject ?? "",
                request.body ?? "",
            ])
        case .review(let number, let action, let body):
            components.append(contentsOf: [
                "review",
                String(number),
                action.rawValue,
                body ?? "",
            ])
        }

        var canonical = ""
        for component in components {
            canonical += "\(component.utf8.count):\(component)"
        }
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func approvalPreview(_ request: GitHubSocketMutationAuthorizationRequest) -> String {
        var lines = [
            "Repository: \(escapedPreview(request.context.repository.displayName))",
            "Pull request: #\(request.intent.pullRequestNumber)",
        ]
        switch request.intent {
        case .merge(let merge):
            lines.append("Action: merge")
            lines.append("Method: \(merge.method.rawValue)")
            lines.append("Delete branch: \(merge.deleteBranch ? "yes" : "no")")
            lines.append("Subject: \(escapedPreview(merge.subject ?? "(none)"))")
            lines.append("Body:\n\(escapedPreview(merge.body ?? "(none)"))")
        case .review(_, let action, let body):
            let actionName = action == .approve ? "approve" : "request changes"
            lines.append("Action: \(actionName)")
            lines.append("Body:\n\(escapedPreview(body ?? "(none)"))")
        }
        return lines.joined(separator: "\n")
    }

    static func escapedPreview(_ value: String) -> String {
        var preview = ""
        for scalar in value.unicodeScalars {
            if scalar == "\\" {
                preview += "\\\\"
            } else if scalar == "\t" {
                preview += "\\t"
            } else if scalar == "\n" {
                preview += "\\n\n"
            } else if scalar == "\r" {
                preview += "\\r"
            } else {
                switch scalar.properties.generalCategory {
                case .control, .format, .lineSeparator, .paragraphSeparator:
                    preview += String(format: "\\u{%04X}", scalar.value)
                default:
                    preview.unicodeScalars.append(scalar)
                }
            }
        }
        return preview
    }
}
