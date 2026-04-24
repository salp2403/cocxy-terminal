// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubModels.swift - Value types decoded from `gh` JSON output.
//
// Every struct is `Sendable`, `Equatable`, and decodable with `decodeIfPresent`
// for any field the host may omit. The tolerant shape is deliberate: `gh`
// releases occasionally rename or drop fields in its `--json` surface, and
// we would rather fall back to safe defaults than surface a JSON decoding
// error to the user.
//
// Dates are decoded via a shared strategy that accepts both
// `2026-04-23T15:47:21Z` (standard ISO8601) and
// `2026-04-23T15:47:21.123Z` (with fractional seconds) because `gh` emits
// both forms depending on the endpoint.

import Foundation

// MARK: - Decoding helper

enum GitHubJSONDecoder {

    /// Preconfigured `JSONDecoder` that every `GitHubModels.decode(...)`
    /// helper uses. The date strategy is tolerant of the two ISO8601 shapes
    /// `gh` emits without requiring callers to pass decoders around.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            let primary = ISO8601DateFormatter()
            primary.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = primary.date(from: raw) { return date }

            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: raw) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(raw)"
            )
        }
        return decoder
    }

    /// Decodes a value from UTF-8 JSON bytes. Wraps the raw
    /// `DecodingError` so callers can log the short reason without leaking
    /// the entire stack to the error banner.
    static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw GitHubCLIError.invalidJSON(reason: "Response is not valid UTF-8")
        }
        do {
            return try makeDecoder().decode(type, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            throw GitHubCLIError.invalidJSON(
                reason: "Missing key \"\(key.stringValue)\" at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            )
        } catch let DecodingError.typeMismatch(_, context) {
            throw GitHubCLIError.invalidJSON(
                reason: "Type mismatch at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            )
        } catch let DecodingError.valueNotFound(_, context) {
            throw GitHubCLIError.invalidJSON(
                reason: "Missing value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            )
        } catch let DecodingError.dataCorrupted(context) {
            throw GitHubCLIError.invalidJSON(
                reason: "Corrupted data at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            )
        } catch {
            throw GitHubCLIError.invalidJSON(reason: "\(error.localizedDescription)")
        }
    }
}

// MARK: - Core value types

struct GitHubUser: Codable, Equatable, Sendable {
    let login: String
    let id: String?

    init(login: String, id: String? = nil) {
        self.login = login
        self.id = id
    }
}

struct GitHubLabel: Codable, Equatable, Sendable, Identifiable {
    let name: String
    let color: String?
    let description: String?

    var id: String { name }

    init(name: String, color: String? = nil, description: String? = nil) {
        self.name = name
        self.color = color
        self.description = description
    }
}

// MARK: - Repository

/// Repository metadata surfaced by `gh repo view --json`.
struct GitHubRepo: Codable, Equatable, Sendable {

    private struct DefaultBranchRef: Codable, Equatable, Sendable {
        let name: String
    }

    let owner: GitHubUser
    let name: String
    let defaultBranch: String
    let url: URL
    let hasIssuesEnabled: Bool
    let isPrivate: Bool
    let isEmpty: Bool
    let description: String?

    var fullName: String { "\(owner.login)/\(name)" }

    init(
        owner: GitHubUser,
        name: String,
        defaultBranch: String,
        url: URL,
        hasIssuesEnabled: Bool = true,
        isPrivate: Bool = false,
        isEmpty: Bool = false,
        description: String? = nil
    ) {
        self.owner = owner
        self.name = name
        self.defaultBranch = defaultBranch
        self.url = url
        self.hasIssuesEnabled = hasIssuesEnabled
        self.isPrivate = isPrivate
        self.isEmpty = isEmpty
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case owner, name, defaultBranchRef, url, hasIssuesEnabled
        case isPrivate, isEmpty, description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.owner = try container.decode(GitHubUser.self, forKey: .owner)
        self.name = try container.decode(String.self, forKey: .name)
        let defaultBranchRef = try container.decodeIfPresent(
            DefaultBranchRef.self,
            forKey: .defaultBranchRef
        )
        self.defaultBranch = defaultBranchRef?.name ?? "main"
        self.url = try container.decode(URL.self, forKey: .url)
        self.hasIssuesEnabled = try container.decodeIfPresent(Bool.self, forKey: .hasIssuesEnabled) ?? true
        self.isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        self.isEmpty = try container.decodeIfPresent(Bool.self, forKey: .isEmpty) ?? false
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(owner, forKey: .owner)
        try container.encode(name, forKey: .name)
        try container.encode(DefaultBranchRef(name: defaultBranch), forKey: .defaultBranchRef)
        try container.encode(url, forKey: .url)
        try container.encode(hasIssuesEnabled, forKey: .hasIssuesEnabled)
        try container.encode(isPrivate, forKey: .isPrivate)
        try container.encode(isEmpty, forKey: .isEmpty)
        try container.encodeIfPresent(description, forKey: .description)
    }
}

// MARK: - Pull request

/// High-level state for a pull request.
///
/// The raw values match the uppercase strings `gh` emits in `--json state`
/// so decoding is a direct rawValue lookup. Unknown values fall back to
/// `.unknown` rather than failing to decode.
enum GitHubPullRequestState: String, Codable, Equatable, Sendable, CaseIterable {
    case open = "OPEN"
    case closed = "CLOSED"
    case merged = "MERGED"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.uppercased() ?? ""
        self = GitHubPullRequestState(rawValue: raw) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .closed: return "Closed"
        case .merged: return "Merged"
        case .unknown: return "Unknown"
        }
    }
}

/// Outcome of the review workflow on a PR.
///
/// `gh` emits this as `REVIEW_REQUIRED`, `APPROVED`, `CHANGES_REQUESTED`
/// or `null` when no review has been requested. We absorb the null as
/// `.none` so the UI does not have to pattern-match on optionality.
enum GitHubReviewDecision: String, Codable, Equatable, Sendable {
    case none
    case reviewRequired = "REVIEW_REQUIRED"
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .none
            return
        }
        let raw = (try? container.decode(String.self))?.uppercased() ?? ""
        self = GitHubReviewDecision(rawValue: raw) ?? .none
    }

    var displayName: String {
        switch self {
        case .none: return "—"
        case .reviewRequired: return "Review required"
        case .approved: return "Approved"
        case .changesRequested: return "Changes requested"
        }
    }
}

/// Pull request summary as returned by `gh pr list --json`.
struct GitHubPullRequest: Codable, Equatable, Sendable, Identifiable {
    let number: Int
    let title: String
    let state: GitHubPullRequestState
    let author: GitHubUser
    let headRefName: String
    let baseRefName: String
    let labels: [GitHubLabel]
    let isDraft: Bool
    let reviewDecision: GitHubReviewDecision
    let url: URL
    let updatedAt: Date

    var id: Int { number }

    init(
        number: Int,
        title: String,
        state: GitHubPullRequestState,
        author: GitHubUser,
        headRefName: String,
        baseRefName: String,
        labels: [GitHubLabel] = [],
        isDraft: Bool = false,
        reviewDecision: GitHubReviewDecision = .none,
        url: URL,
        updatedAt: Date
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.author = author
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.labels = labels
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
        self.url = url
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case number, title, state, author, headRefName, baseRefName
        case labels, isDraft, reviewDecision, url, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.number = try container.decode(Int.self, forKey: .number)
        self.title = try container.decode(String.self, forKey: .title)
        self.state = try container.decodeIfPresent(GitHubPullRequestState.self, forKey: .state) ?? .unknown
        self.author = try container.decodeIfPresent(GitHubUser.self, forKey: .author) ?? GitHubUser(login: "—")
        self.headRefName = try container.decodeIfPresent(String.self, forKey: .headRefName) ?? ""
        self.baseRefName = try container.decodeIfPresent(String.self, forKey: .baseRefName) ?? ""
        self.labels = try container.decodeIfPresent([GitHubLabel].self, forKey: .labels) ?? []
        self.isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        self.reviewDecision = try container.decodeIfPresent(GitHubReviewDecision.self, forKey: .reviewDecision) ?? .none
        self.url = try container.decode(URL.self, forKey: .url)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Issue

/// Open / closed state for a GitHub issue.
enum GitHubIssueState: String, Codable, Equatable, Sendable, CaseIterable {
    case open = "OPEN"
    case closed = "CLOSED"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.uppercased() ?? ""
        self = GitHubIssueState(rawValue: raw) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .closed: return "Closed"
        case .unknown: return "Unknown"
        }
    }
}

/// Issue summary as returned by `gh issue list --json`.
///
/// `gh` returns `comments` as an array of comment objects; we only need
/// the count for the UI so the decoder folds it to an integer up front.
/// Conformance is intentionally limited to `Decodable` — the app only
/// consumes issues, never writes them back — so the synthesized encoder
/// does not have to mirror the custom `comments → commentCount` fold.
struct GitHubIssue: Decodable, Equatable, Sendable, Identifiable {
    let number: Int
    let title: String
    let state: GitHubIssueState
    let author: GitHubUser
    let labels: [GitHubLabel]
    let commentCount: Int
    let url: URL
    let updatedAt: Date

    var id: Int { number }

    init(
        number: Int,
        title: String,
        state: GitHubIssueState,
        author: GitHubUser,
        labels: [GitHubLabel] = [],
        commentCount: Int = 0,
        url: URL,
        updatedAt: Date
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.author = author
        self.labels = labels
        self.commentCount = commentCount
        self.url = url
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case number, title, state, author, labels, comments, url, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.number = try container.decode(Int.self, forKey: .number)
        self.title = try container.decode(String.self, forKey: .title)
        self.state = try container.decodeIfPresent(GitHubIssueState.self, forKey: .state) ?? .unknown
        self.author = try container.decodeIfPresent(GitHubUser.self, forKey: .author) ?? GitHubUser(login: "—")
        self.labels = try container.decodeIfPresent([GitHubLabel].self, forKey: .labels) ?? []

        // `gh` emits the comments field as either an array (newer versions)
        // or an integer count (older versions). Both paths fold into the
        // same integer to keep the UI trivial.
        if let comments = try? container.decodeIfPresent([[String: String]].self, forKey: .comments) {
            self.commentCount = comments.count
        } else if let count = try? container.decodeIfPresent(Int.self, forKey: .comments) {
            self.commentCount = count
        } else {
            self.commentCount = 0
        }

        self.url = try container.decode(URL.self, forKey: .url)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Check

/// Raw status of a check run, matching the strings `gh` emits in
/// `--json status` for `gh pr checks`.
enum GitHubCheckStatus: String, Codable, Equatable, Sendable {
    case queued = "QUEUED"
    case inProgress = "IN_PROGRESS"
    case completed = "COMPLETED"
    case pending = "PENDING"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.uppercased() ?? ""
        self = GitHubCheckStatus(rawValue: raw) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .pending: return "Pending"
        case .unknown: return "Unknown"
        }
    }
}

/// Resolution of a completed check. `none` is surfaced when the check has
/// not finished (and therefore has no conclusion to report).
enum GitHubCheckConclusion: String, Codable, Equatable, Sendable {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case neutral = "NEUTRAL"
    case cancelled = "CANCELLED"
    case skipped = "SKIPPED"
    case timedOut = "TIMED_OUT"
    case actionRequired = "ACTION_REQUIRED"
    case stale = "STALE"
    case startupFailure = "STARTUP_FAILURE"
    case none

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .none
            return
        }
        let raw = (try? container.decode(String.self))?.uppercased() ?? ""
        if raw.isEmpty {
            self = .none
            return
        }
        self = GitHubCheckConclusion(rawValue: raw) ?? .none
    }

    var displayName: String {
        switch self {
        case .success: return "Success"
        case .failure: return "Failure"
        case .neutral: return "Neutral"
        case .cancelled: return "Cancelled"
        case .skipped: return "Skipped"
        case .timedOut: return "Timed out"
        case .actionRequired: return "Action required"
        case .stale: return "Stale"
        case .startupFailure: return "Startup failure"
        case .none: return "—"
        }
    }
}

/// Check run summary as returned by `gh pr checks <number> --json`.
///
/// `Decodable` only because the CodingKeys include `link` as an alias for
/// `detailsUrl`, which would confuse the synthesized encoder. We never
/// serialize checks back to JSON, so encoder synthesis is unnecessary.
struct GitHubCheck: Decodable, Equatable, Sendable, Identifiable {
    let name: String
    let status: GitHubCheckStatus
    let conclusion: GitHubCheckConclusion
    let detailsUrl: URL?
    let startedAt: Date?
    let completedAt: Date?

    var id: String { name }

    init(
        name: String,
        status: GitHubCheckStatus,
        conclusion: GitHubCheckConclusion = .none,
        detailsUrl: URL? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.detailsUrl = detailsUrl
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case name, status, conclusion, detailsUrl, link, startedAt, completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.status = try container.decodeIfPresent(GitHubCheckStatus.self, forKey: .status) ?? .unknown
        self.conclusion = try container.decodeIfPresent(GitHubCheckConclusion.self, forKey: .conclusion) ?? .none
        // `gh pr checks` exposes the URL under `link`; `gh run list --json`
        // exposes it under `detailsUrl`. Accept either.
        self.detailsUrl = (try? container.decodeIfPresent(URL.self, forKey: .detailsUrl))
            ?? (try? container.decodeIfPresent(URL.self, forKey: .link))
            ?? nil
        self.startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

// MARK: - Auth status

/// Parsed outcome of `gh auth status`.
///
/// `gh auth status` does not support `--json`, so this struct is produced
/// by `GitHubAuthStatusParser.parse(_:)` from the textual output. The
/// parser lives inside this file to keep the domain shape and its only
/// consumer side-by-side.
struct GitHubAuthStatus: Equatable, Sendable {

    /// Whether at least one host reports a logged-in account.
    let isAuthenticated: Bool
    /// Primary GitHub host (typically `github.com`).
    let host: String
    /// Logged-in user handle. `nil` when logged out.
    let login: String?
    /// Scopes attached to the stored token.
    let scopes: [String]

    /// Whether the token carries the `workflow` scope. Required for any
    /// tooling that dispatches GitHub Actions workflows (Fase 9 CLI).
    var hasWorkflowScope: Bool { scopes.contains("workflow") }

    /// Whether the token carries the `repo` scope. Required for pull
    /// request read/write surfaces.
    var hasRepoScope: Bool { scopes.contains("repo") }

    static let loggedOut = GitHubAuthStatus(
        isAuthenticated: false,
        host: "github.com",
        login: nil,
        scopes: []
    )
}

/// Text-format parser for `gh auth status`.
///
/// Expected input shape (abridged):
/// ```
/// github.com
///   ✓ Logged in to github.com account <login> (keyring)
///   - Token scopes: 'repo', 'workflow', …
/// ```
/// Older `gh` releases use "Logged in to github.com as <login>" — both
/// forms are accepted.
enum GitHubAuthStatusParser {

    private static let loggedInRegex = try? NSRegularExpression(
        pattern: #"logged in to ([\w.-]+) (?:as|account) ([\w-]+)"#,
        options: [.caseInsensitive]
    )

    private static let scopesRegex = try? NSRegularExpression(
        pattern: #"token scopes:\s*(.+)$"#,
        options: [.caseInsensitive, .anchorsMatchLines]
    )

    /// Parses the `gh auth status` stdout/stderr output.
    ///
    /// If the output does not contain a "logged in" line for any host, the
    /// return value is `.loggedOut` regardless of other content.
    static func parse(_ output: String) -> GitHubAuthStatus {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .loggedOut }

        let nsOutput = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsOutput.length)

        guard let regex = loggedInRegex,
              let match = regex.firstMatch(in: trimmed, range: fullRange),
              match.numberOfRanges >= 3 else {
            return .loggedOut
        }

        let host = nsOutput.substring(with: match.range(at: 1))
        let login = nsOutput.substring(with: match.range(at: 2))

        var scopes: [String] = []
        if let scopesRegex,
           let scopeMatch = scopesRegex.firstMatch(in: trimmed, range: fullRange),
           scopeMatch.numberOfRanges >= 2 {
            let raw = nsOutput.substring(with: scopeMatch.range(at: 1))
            scopes = Self.extractScopes(from: raw)
        }

        return GitHubAuthStatus(
            isAuthenticated: true,
            host: host,
            login: login,
            scopes: scopes
        )
    }

    /// Pulls every single-quoted token out of the scopes line.
    ///
    /// `gh` prints `'repo', 'workflow', 'gist'`; we strip the quotes and
    /// whitespace so the resulting strings are usable as Set keys.
    private static func extractScopes(from raw: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"'([^']+)'"#, options: []) else {
            return []
        }
        let nsRaw = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: nsRaw.length))
        return matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            return nsRaw.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
        }
    }
}
