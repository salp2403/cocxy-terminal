// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubPaneRow.swift - Reusable row components rendering a single
// pull request, issue, or check inside the GitHub pane list.
//
// Each row is a plain `View` so the pane's `List` (or `LazyVStack`)
// can compose them without any AppKit hosting.

import SwiftUI
import AppKit

// MARK: - Pull request row

/// Row rendering a single pull request summary line.
struct GitHubPullRequestRow: View {
    let pullRequest: GitHubPullRequest
    let isSelected: Bool
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .english)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSystemImage)
                .foregroundColor(statusTint)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(pullRequest.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text("#\(pullRequest.number)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(pullRequest.author.login)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if !pullRequest.headRefName.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(pullRequest.headRefName)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(for: pullRequest, using: localizer))
    }

    static func accessibilityLabel(
        for pullRequest: GitHubPullRequest,
        using localizer: AppLocalizer
    ) -> String {
        String(
            format: localizer.string(
                "github.pane.row.pr.accessibility",
                fallback: "PR #%d: %@ by %@"
            ),
            pullRequest.number,
            pullRequest.title,
            pullRequest.author.login
        )
    }

    private var statusSystemImage: String {
        if pullRequest.isDraft { return "circle.dashed" }
        switch pullRequest.state {
        case .open: return "arrow.triangle.pull"
        case .closed: return "xmark.circle"
        case .merged: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var statusTint: Color {
        if pullRequest.isDraft { return .secondary }
        switch pullRequest.state {
        case .open: return Color.green
        case .closed: return Color.red
        case .merged: return Color.purple
        case .unknown: return .secondary
        }
    }
}

// MARK: - Issue row

struct GitHubIssueRow: View {
    let issue: GitHubIssue
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .english)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSystemImage)
                .foregroundColor(statusTint)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text("#\(issue.number)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(issue.author.login)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if issue.commentCount > 0 {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.6))
                        Label("\(issue.commentCount)", systemImage: "bubble.right")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(for: issue, using: localizer))
    }

    static func accessibilityLabel(
        for issue: GitHubIssue,
        using localizer: AppLocalizer
    ) -> String {
        String(
            format: localizer.string(
                "github.pane.row.issue.accessibility",
                fallback: "Issue #%d: %@ by %@"
            ),
            issue.number,
            issue.title,
            issue.author.login
        )
    }

    private var statusSystemImage: String {
        switch issue.state {
        case .open: return "exclamationmark.circle"
        case .closed: return "checkmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    private var statusTint: Color {
        switch issue.state {
        case .open: return Color.green
        case .closed: return Color.secondary
        case .unknown: return .secondary
        }
    }
}

// MARK: - Check row

struct GitHubCheckRow: View {
    let check: GitHubCheck
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .english)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSystemImage)
                .foregroundColor(statusTint)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(check.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(Self.statusSummary(for: check, using: localizer))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(for: check, using: localizer))
    }

    static func statusSummary(
        for check: GitHubCheck,
        using localizer: AppLocalizer
    ) -> String {
        [
            check.status.localizedDisplayName(using: localizer),
            check.conclusion.localizedDisplayName(using: localizer),
        ].joined(separator: " • ")
    }

    static func accessibilityLabel(
        for check: GitHubCheck,
        using localizer: AppLocalizer
    ) -> String {
        String(
            format: localizer.string(
                "github.pane.row.check.accessibility",
                fallback: "Check %@: %@, conclusion %@"
            ),
            check.name,
            check.status.localizedDisplayName(using: localizer),
            check.conclusion.localizedDisplayName(using: localizer)
        )
    }

    private var statusSystemImage: String {
        switch check.conclusion {
        case .success: return "checkmark.circle.fill"
        case .failure, .startupFailure, .timedOut: return "xmark.octagon.fill"
        case .cancelled, .skipped, .stale: return "minus.circle"
        case .neutral, .actionRequired: return "exclamationmark.circle"
        case .none:
            return isActiveCheck ? "arrow.triangle.2.circlepath" : "circle"
        }
    }

    private var statusTint: Color {
        switch check.conclusion {
        case .success: return Color.green
        case .failure, .startupFailure, .timedOut: return Color.red
        case .cancelled, .skipped, .stale: return .secondary
        case .neutral, .actionRequired: return .orange
        case .none:
            return isActiveCheck ? .blue : .secondary
        }
    }

    private var isActiveCheck: Bool {
        switch check.status {
        case .queued, .pending, .inProgress:
            return true
        case .completed, .unknown:
            return false
        }
    }
}

// MARK: - Review thread row

struct GitHubReviewThreadRow: View {
    let thread: GitHubPullRequestReviewThread
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .english)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSystemImage)
                .foregroundColor(statusTint)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(thread.displayLocation)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(Self.statusTitle(for: thread, using: localizer))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(statusTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(statusTint.opacity(0.14))
                        )
                }

                if let firstComment = thread.comments.first {
                    Text(firstComment.body)
                        .font(.system(size: 12))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        String(
                            format: localizer.string(
                                "github.pane.reviewThreads.author",
                                fallback: "by %@"
                            ),
                            firstComment.authorLogin
                        )
                    )
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Label(
                        String(
                            format: localizer.string(
                                "github.pane.reviewThreads.comments",
                                fallback: "%d comments"
                            ),
                            thread.comments.count
                        ),
                        systemImage: "bubble.right"
                    )
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                    if thread.isOutdated {
                        Label(
                            localizer.string(
                                "github.pane.reviewThreads.outdated",
                                fallback: "Outdated"
                            ),
                            systemImage: "clock.arrow.circlepath"
                        )
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(for: thread, using: localizer))
    }

    static func statusTitle(
        for thread: GitHubPullRequestReviewThread,
        using localizer: AppLocalizer
    ) -> String {
        switch thread.state {
        case .unresolved:
            return localizer.string("github.pane.reviewThreads.unresolved", fallback: "Unresolved")
        case .resolved:
            return localizer.string("github.pane.reviewThreads.resolved", fallback: "Resolved")
        }
    }

    static func accessibilityLabel(
        for thread: GitHubPullRequestReviewThread,
        using localizer: AppLocalizer
    ) -> String {
        String(
            format: localizer.string(
                "github.pane.row.reviewThread.accessibility",
                fallback: "%@ review thread at %@ with %d comments"
            ),
            statusTitle(for: thread, using: localizer),
            thread.displayLocation,
            thread.comments.count
        )
    }

    private var statusSystemImage: String {
        switch thread.state {
        case .unresolved: return "exclamationmark.bubble"
        case .resolved: return "checkmark.circle"
        }
    }

    private var statusTint: Color {
        switch thread.state {
        case .unresolved: return .orange
        case .resolved: return .green
        }
    }
}

extension GitHubCheckStatus {
    func localizedDisplayName(using localizer: AppLocalizer) -> String {
        switch self {
        case .queued:
            return localizer.string("github.pane.check.status.queued", fallback: displayName)
        case .inProgress:
            return localizer.string("github.pane.check.status.inProgress", fallback: displayName)
        case .completed:
            return localizer.string("github.pane.check.status.completed", fallback: displayName)
        case .pending:
            return localizer.string("github.pane.check.status.pending", fallback: displayName)
        case .unknown:
            return localizer.string("github.pane.check.status.unknown", fallback: displayName)
        }
    }
}

extension GitHubCheckConclusion {
    func localizedDisplayName(using localizer: AppLocalizer) -> String {
        switch self {
        case .success:
            return localizer.string("github.pane.check.conclusion.success", fallback: displayName)
        case .failure:
            return localizer.string("github.pane.check.conclusion.failure", fallback: displayName)
        case .neutral:
            return localizer.string("github.pane.check.conclusion.neutral", fallback: displayName)
        case .cancelled:
            return localizer.string("github.pane.check.conclusion.cancelled", fallback: displayName)
        case .skipped:
            return localizer.string("github.pane.check.conclusion.skipped", fallback: displayName)
        case .timedOut:
            return localizer.string("github.pane.check.conclusion.timedOut", fallback: displayName)
        case .actionRequired:
            return localizer.string("github.pane.check.conclusion.actionRequired", fallback: displayName)
        case .stale:
            return localizer.string("github.pane.check.conclusion.stale", fallback: displayName)
        case .startupFailure:
            return localizer.string("github.pane.check.conclusion.startupFailure", fallback: displayName)
        case .none:
            return displayName
        }
    }
}
