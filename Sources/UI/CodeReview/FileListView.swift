// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FileListView.swift - Changed file sidebar for the review panel.

import SwiftUI

struct FileListView: View {
    let diffs: [FileDiff]
    let commentCount: (String) -> Int
    @Binding var selectedPath: String?

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
                        selectedPath = diff.filePath
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(diff.displayName), \(accessibilityStatus(diff.status)), plus \(diff.additions), minus \(diff.deletions)")
                    .accessibilityHint("Select this file to review its hunks")
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: CocxyColors.mantle))
    }
}

private func accessibilityStatus(_ status: FileStatus) -> String {
    switch status {
    case .added, .untracked:
        return "added"
    case .modified:
        return "modified"
    case .deleted:
        return "deleted"
    case .renamed:
        return "renamed"
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
