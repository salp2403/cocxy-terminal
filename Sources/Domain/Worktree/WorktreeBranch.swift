// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeBranch.swift - Branch-name generation and git-ref
// sanitisation for cocxy-managed worktrees.

import Foundation

/// Pure helpers that turn a user-configured template into a valid git
/// branch name for a cocxy worktree.
///
/// The template language is deliberately tiny — three curly-brace
/// placeholders — so there is no parser to reason about and the output
/// is always predictable.
///
/// Placeholders:
///   - `{agent}` — detected agent name (lowercase), sanitised against
///     `git-check-ref-format(1)`. When the caller does not have an
///     agent name, `fallbackAgentName` is substituted.
///   - `{id}` — the worktree id produced by `WorktreeID.generate`.
///     Always alphanumeric lowercase; left as-is.
///   - `{date}` — `yyyy-MM-dd` in `en_US_POSIX` formatting so the
///     output is deterministic across locales.
///
/// Callers pass the raw template verbatim; this helper does not trust
/// the template itself (it may arrive from the user's config), so we
/// also sanitise the *post-expansion* string against the git rules.
enum WorktreeBranch {

    /// Fallback value substituted for `{agent}` when the caller cannot
    /// identify the agent (e.g. `cocxy worktree add` without a tab in
    /// an agent session, or a sanitisation pass that removes every
    /// character of the input).
    static let fallbackAgentName: String = "worktree"

    /// Expands the template into a full branch name.
    ///
    /// - Parameters:
    ///   - template: Raw template, typically `config.worktree.branchTemplate`.
    ///   - agent: Agent display/binary name. `nil` or all-invalid names
    ///     fall back to `fallbackAgentName`.
    ///   - id: Pre-generated id. Caller is responsible for calling
    ///     `WorktreeID.generate` first; this helper only substitutes.
    ///   - date: Timestamp driving `{date}`. Defaults to `Date()` so
    ///     production callers stay one-liners, tests inject a fixed
    ///     date.
    ///   - calendar: Calendar used for the `{date}` rendering. Tests
    ///     inject a fixed calendar to avoid environment-dependent
    ///     output; production keeps the default POSIX calendar.
    ///
    /// - Returns: A branch name safe to pass to `git worktree add -b`.
    static func expand(
        template: String,
        agent: String?,
        id: String,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let safeAgent = normalisedAgentName(agent)
        let dateString = renderDate(date, timeZone: timeZone)

        let expanded = template
            .replacingOccurrences(of: "{agent}", with: safeAgent)
            .replacingOccurrences(of: "{id}", with: id)
            .replacingOccurrences(of: "{date}", with: dateString)

        return sanitiseFullBranchName(expanded)
    }

    /// Sanitises a single branch-component by replacing characters
    /// outside `[A-Za-z0-9._-]` with a dash, collapsing consecutive
    /// dashes, and stripping any leading or trailing non-alphanumeric
    /// characters.
    ///
    /// This is the stricter of the two sanitisers: it refuses even
    /// legal git ref characters like `/` because a *component* should
    /// never contain a slash — the template itself positions slashes.
    static func sanitizeGitRefComponent(_ name: String) -> String {
        guard !name.isEmpty else { return "" }

        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-._"))

        var buffer = ""
        var lastWasDash = false
        for scalar in name.unicodeScalars {
            if allowed.contains(scalar) {
                buffer.unicodeScalars.append(scalar)
                lastWasDash = (scalar == "-")
            } else if !lastWasDash {
                buffer.append("-")
                lastWasDash = true
            }
        }

        // Collapse `..` → `-` so `@..tag` style inputs never propagate
        // a double-dot to the branch name.
        while buffer.contains("..") {
            buffer = buffer.replacingOccurrences(of: "..", with: "-")
        }

        // Drop leading / trailing characters that are not alphanumeric
        // until the string starts and ends on a letter or digit. This
        // eliminates the `starts with .` and `ends with .lock` edge
        // cases the git reference format forbids.
        while let first = buffer.unicodeScalars.first,
              !CharacterSet.alphanumerics.contains(first) {
            buffer.removeFirst()
        }
        while let last = buffer.unicodeScalars.last,
              !CharacterSet.alphanumerics.contains(last) {
            buffer.removeLast()
        }

        return buffer
    }

    // MARK: - Private helpers

    /// Applies full-branch sanitisation — only slashes are permitted in
    /// addition to the component-allowed set — and trims the result.
    private static func sanitiseFullBranchName(_ branch: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-._/"))

        var buffer = ""
        var lastWasDash = false
        for scalar in branch.unicodeScalars {
            if allowed.contains(scalar) {
                buffer.unicodeScalars.append(scalar)
                lastWasDash = (scalar == "-")
            } else if !lastWasDash {
                buffer.append("-")
                lastWasDash = true
            }
        }

        // `//` → `/` (collapse repeated slashes); `..` → `-` (git
        // forbids double-dots anywhere in refs).
        while buffer.contains("//") {
            buffer = buffer.replacingOccurrences(of: "//", with: "/")
        }
        while buffer.contains("..") {
            buffer = buffer.replacingOccurrences(of: "..", with: "-")
        }

        // Strip characters git rejects at the edges (`.`, `/`, `-`).
        while let first = buffer.first, "./-".contains(first) {
            buffer.removeFirst()
        }
        while let last = buffer.last, "./-".contains(last) {
            buffer.removeLast()
        }

        return buffer.isEmpty ? fallbackAgentName : buffer
    }

    private static func normalisedAgentName(_ agent: String?) -> String {
        guard let agent else { return fallbackAgentName }
        let sanitised = sanitizeGitRefComponent(agent)
        return sanitised.isEmpty ? fallbackAgentName : sanitised
    }

    private static func renderDate(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
