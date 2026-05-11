// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BranchPickerView.swift - Searchable local/remote branch picker.

import SwiftUI

struct BranchPickerView: View {
    let branches: [GitBranch]
    var worktreeEntries: [WorktreeManifest.WorktreeEntry] = []
    let selectedBranchName: String?
    @Binding var searchText: String
    var sourceControlErrorMessage: String?
    var onRefresh: () -> Void
    var onSelect: (GitBranch) -> Void
    var onCreateBranch: () -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .english)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let sourceControlErrorMessage {
                SourceControlInlineMessage(message: sourceControlErrorMessage, systemImage: "exclamationmark.triangle")
            }
            if !worktreeEntries.isEmpty {
                WorktreeBranchPickerView(
                    entries: worktreeEntries,
                    onSelect: { entry in
                        if let branch = branches.first(where: { $0.name == entry.branch }) {
                            onSelect(branch)
                        } else {
                            onSelect(GitBranch(name: entry.branch, isRemote: false))
                        }
                    },
                    localizer: localizer
                )
                Divider().opacity(0.4)
            }
            if filteredBranches.isEmpty {
                SourceControlEmptyState(
                    title: localizer.string("github.branches.empty", fallback: "No branches"),
                    systemImage: "arrow.triangle.branch"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredBranches) { branch in
                            Button(action: { onSelect(branch) }) {
                                BranchPickerRow(
                                    branch: branch,
                                    isSelected: selectedBranchName == branch.name
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    static func filteredBranches(_ branches: [GitBranch], searchText: String) -> [GitBranch] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return branches }
        return branches.filter { branch in
            branch.name.lowercased().contains(needle) ||
                branch.upstreamName?.lowercased().contains(needle) == true ||
                branch.lastCommitSubject?.lowercased().contains(needle) == true
        }
    }

    private var filteredBranches: [GitBranch] {
        Self.filteredBranches(branches, searchText: searchText)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField(
                localizer.string("github.branches.search", fallback: "Search branches"),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(localizer.string("github.branches.refresh", fallback: "Refresh branches"))

            Button(action: onCreateBranch) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(localizer.string("github.branches.create", fallback: "Create branch"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct BranchPickerRow: View {
    let branch: GitBranch
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .foregroundColor(branch.isCurrent ? .accentColor : .secondary)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(branch.name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if branch.isRemote {
                        Text("remote")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    if let lastCommitHash = branch.lastCommitHash {
                        Text(lastCommitHash)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if let subject = branch.lastCommitSubject {
                        Text(subject)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
        .accessibilityLabel(branch.name)
    }
}
