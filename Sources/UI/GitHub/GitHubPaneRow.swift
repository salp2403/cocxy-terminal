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
        .accessibilityLabel("PR #\(pullRequest.number): \(pullRequest.title) by \(pullRequest.author.login)")
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
        .accessibilityLabel("Issue #\(issue.number): \(issue.title) by \(issue.author.login)")
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

                Text("\(check.status.displayName) • \(check.conclusion.displayName)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Check \(check.name): \(check.status.displayName), conclusion \(check.conclusion.displayName)")
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
