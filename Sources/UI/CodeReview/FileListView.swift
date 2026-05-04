// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FileListView.swift - Changed file sidebar for the review panel.

import SwiftUI

struct CodeReviewExternalEditorAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let open: (String) -> Void
}

struct FileListView: View {
    let diffs: [FileDiff]
    let commentCount: (String) -> Int
    let selectedPath: String?
    let externalEditorActions: [CodeReviewExternalEditorAction]
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(diffs) { diff in
                    FileListRow(
                        diff: diff,
                        commentCount: commentCount(diff.filePath),
                        isSelected: selectedPath == diff.filePath
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture {
                        onSelect(diff.filePath)
                    }
                    .contextMenu {
                        ForEach(externalEditorActions) { action in
                            Button {
                                action.open(diff.filePath)
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(
                        Self.localizedAccessibilityLabel(
                            displayName: diff.displayName,
                            status: diff.status,
                            additions: diff.additions,
                            deletions: diff.deletions,
                            using: localizer
                        )
                    )
                    .accessibilityHint(Self.localizedAccessibilityHint(using: localizer))
                }
            }
            .padding(10)
        }
        .glassPanelBackground()
    }

    static func localizedAccessibilityLabel(
        displayName: String,
        status: FileStatus,
        additions: Int,
        deletions: Int,
        using localizer: AppLocalizer
    ) -> String {
        String(
            format: localizer.string(
                "codeReview.fileList.accessibility.label",
                fallback: "%@, %@, plus %d, minus %d"
            ),
            displayName,
            localizedAccessibilityStatus(status, using: localizer),
            additions,
            deletions
        )
    }

    static func localizedAccessibilityHint(using localizer: AppLocalizer) -> String {
        localizer.string(
            "codeReview.fileList.accessibility.hint",
            fallback: "Select this file to review its hunks"
        )
    }

    static func localizedAccessibilityStatus(_ status: FileStatus, using localizer: AppLocalizer) -> String {
        switch status {
        case .added, .untracked:
            return localizer.string("codeReview.fileList.status.added", fallback: "added")
        case .modified:
            return localizer.string("codeReview.fileList.status.modified", fallback: "modified")
        case .deleted:
            return localizer.string("codeReview.fileList.status.deleted", fallback: "deleted")
        case .renamed:
            return localizer.string("codeReview.fileList.status.renamed", fallback: "renamed")
        }
    }
}

private struct FileListRow: View {
    let diff: FileDiff
    let commentCount: Int
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusChip

                VStack(alignment: .leading, spacing: 2) {
                    Text(diff.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(diff.filePath)
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6)

                if let agentName = diff.agentName {
                    Text(agentName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(nsColor: CocxyColors.blue))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: CocxyColors.blue).opacity(0.12))
                        )
                }
            }

            HStack(spacing: 8) {
                statPill(text: "+\(diff.additions)", color: CocxyColors.green)
                statPill(text: "-\(diff.deletions)", color: CocxyColors.red)

                if commentCount > 0 {
                    statPill(text: "\(commentCount) comments", color: CocxyColors.yellow)
                }

                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isSelected
                    ? Color(nsColor: CocxyColors.surface0)
                    : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected
                    ? Color(nsColor: CocxyColors.blue).opacity(0.45)
                    : Color(nsColor: CocxyColors.surface0),
                    lineWidth: 1
                )
        )
    }

    private var statusChip: some View {
        Text(diff.status.rawValue)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(Color(nsColor: statusColor))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: statusColor).opacity(0.14))
            )
    }

    private func statPill(text: String, color: NSColor) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(Color(nsColor: color))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color(nsColor: color).opacity(0.10))
            )
    }

    private var statusColor: NSColor {
        switch diff.status {
        case .added, .untracked:
            return CocxyColors.green
        case .modified:
            return CocxyColors.blue
        case .deleted:
            return CocxyColors.red
        case .renamed:
            return CocxyColors.mauve
        }
    }
}
