// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeBranchPickerView.swift - Open worktree branch shortcuts.

import SwiftUI

struct WorktreeBranchPickerView: View {
    let entries: [WorktreeManifest.WorktreeEntry]
    var onSelect: (WorktreeManifest.WorktreeEntry) -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .english)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localizer.string("github.worktrees.title", fallback: "Worktrees"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
            ForEach(entries) { entry in
                Button(action: { onSelect(entry) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.connected.to.line.below")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.branch)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(entry.path.path)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}
