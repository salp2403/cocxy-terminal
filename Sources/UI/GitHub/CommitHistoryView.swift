// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommitHistoryView.swift - Scrollable commit timeline for Source Control.

import SwiftUI

struct CommitHistoryView: View {
    let commits: [GitCommit]
    let selectedCommitHash: String?
    @Binding var searchText: String
    var sourceControlErrorMessage: String?
    var onRefresh: () -> Void
    var onSelect: (GitCommit) -> Void
    var onCreateBranch: (GitCommit?) -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .english)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let sourceControlErrorMessage {
                SourceControlInlineMessage(message: sourceControlErrorMessage, systemImage: "exclamationmark.triangle")
            }
            if filteredCommits.isEmpty {
                SourceControlEmptyState(
                    title: localizer.string("github.commits.empty", fallback: "No commits"),
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredCommits) { commit in
                            Button(action: { onSelect(commit) }) {
                                CommitHistoryRow(
                                    commit: commit,
                                    isSelected: selectedCommitHash == commit.hash
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(
                                    localizer.string(
                                        "github.commits.createBranchHere",
                                        fallback: "Create Branch Here..."
                                    )
                                ) {
                                    onCreateBranch(commit)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    static func filteredCommits(_ commits: [GitCommit], searchText: String) -> [GitCommit] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return commits }
        return commits.filter { commit in
            commit.hash.lowercased().contains(needle) ||
                commit.shortHash.lowercased().contains(needle) ||
                commit.subject.lowercased().contains(needle) ||
                commit.authorName.lowercased().contains(needle) ||
                commit.authorEmail.lowercased().contains(needle) ||
                commit.refs.contains { $0.lowercased().contains(needle) }
        }
    }

    private var filteredCommits: [GitCommit] {
        Self.filteredCommits(commits, searchText: searchText)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField(
                localizer.string("github.commits.search", fallback: "Search commits"),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(localizer.string("github.commits.refresh", fallback: "Refresh commits"))

            Button(action: { onCreateBranch(nil) }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(localizer.string("github.commits.createBranch", fallback: "Create branch"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
private struct CommitHistoryRow: View {
    let commit: GitCommit
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
                    .frame(width: 9, height: 9)
                    .padding(.top, 6)
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(commit.subject)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(commit.shortHash)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(commit.authorName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let ref = commit.refs.first {
                        Text(ref)
                            .font(.system(size: 10, weight: .semibold))
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
        .accessibilityLabel("\(commit.shortHash) \(commit.subject)")
    }
}
