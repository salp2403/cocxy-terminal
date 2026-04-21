// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ReviewToolbarView.swift - Bottom toolbar for the review panel.

import SwiftUI

struct ReviewToolbarView: View {
    @ObservedObject var viewModel: CodeReviewPanelViewModel

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    stat(text: "\(viewModel.currentDiffs.count) files", color: CocxyColors.blue)
                    stat(text: "+\(totalAdditions)", color: CocxyColors.green)
                    stat(text: "-\(totalDeletions)", color: CocxyColors.red)
                    if viewModel.pendingCommentCount > 0 {
                        stat(text: "\(viewModel.pendingCommentCount) comments", color: CocxyColors.yellow)
                    }
                    if !viewModel.reviewRounds.isEmpty {
                        stat(text: "\(viewModel.reviewRounds.count) rounds", color: CocxyColors.mauve)
                    }
                    if let gitStatus = viewModel.gitStatus {
                        stat(text: gitStatus.summary, color: CocxyColors.sky)
                    }
                    if !viewModel.reviewAgentSessions.isEmpty {
                        stat(text: "\(viewModel.reviewAgentSessions.count) agents", color: CocxyColors.blue)
                    }
                    if viewModel.reviewSubagentCount > 0 {
                        stat(text: "\(viewModel.reviewSubagentCount) subagents", color: CocxyColors.mauve)
                    }
                    if viewModel.reviewTouchedFileCount > 0 {
                        stat(text: "\(viewModel.reviewTouchedFileCount) touched", color: CocxyColors.green)
                    }
                    if viewModel.reviewConflictCount > 0 {
                        stat(text: "\(viewModel.reviewConflictCount) conflicts", color: CocxyColors.red)
                    }
                    ReviewKeyboardHintsButton()
                }
            }
            .frame(height: 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Picker("Diff Mode", selection: $viewModel.diffMode) {
                        ForEach(DiffMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.diffMode) { _, _ in
                        viewModel.refreshDiffs()
                    }
                    .accessibilityHint("Switch the review comparison mode")

                    Button {
                        viewModel.refreshDiffs()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Reload the current review diff")

                    Button {
                        viewModel.openSelectedFileInEditor()
                    } label: {
                        Label("Edit File", systemImage: "curlybraces")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.selectedFileDiff == nil)
                    .accessibilityHint("Open the selected file in the inline review editor")

                    Button {
                        viewModel.toggleGitWorkflowVisibility()
                    } label: {
                        Label(
                            viewModel.isGitWorkflowVisible ? "Hide Git" : "Git",
                            systemImage: "arrow.triangle.branch"
                        )
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Show branch, commit, and push controls inside the review panel")

                    if viewModel.pendingCommentCount > 0 {
                        Button(role: .destructive) {
                            viewModel.discardPendingComments()
                        } label: {
                            Label("Discard Drafts", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Clear all pending inline comments")
                    }

                    Button {
                        viewModel.submitComments()
                    } label: {
                        Label(
                            viewModel.pendingCommentCount == 0
                                ? "Submit"
                                : "Submit \(viewModel.pendingCommentCount)",
                            systemImage: "paperplane.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.pendingCommentCount == 0)
                    .accessibilityHint("Send all pending comments back to the originating agent")
                }
            }
            .frame(height: 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: CocxyColors.mantle).opacity(0.98))
    }

    private var totalAdditions: Int {
        viewModel.currentDiffs.reduce(0) { $0 + $1.additions }
    }

    private var totalDeletions: Int {
        viewModel.currentDiffs.reduce(0) { $0 + $1.deletions }
    }

    private func stat(text: String, color: NSColor) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(Color(nsColor: color))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(nsColor: color).opacity(0.10))
            )
    }
}

private struct ReviewKeyboardHintsButton: View {
    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
        }
        .buttonStyle(.plain)
        .help("Review shortcuts")
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review Shortcuts")
                    .font(.system(size: 13, weight: .bold))

                ReviewShortcutRow(keys: "j / k", description: "Next / previous hunk")
                ReviewShortcutRow(keys: "n / p", description: "Next / previous file")
                ReviewShortcutRow(keys: "c", description: "Comment current line")
                ReviewShortcutRow(keys: "a / r", description: "Accept / reject hunk")
                ReviewShortcutRow(keys: "d", description: "Cycle diff mode")
                ReviewShortcutRow(keys: "Cmd+Enter", description: "Submit all comments")
                ReviewShortcutRow(keys: "Esc", description: "Cancel comment / close panel")
            }
            .padding(16)
            .frame(width: 250)
            .background(Color(nsColor: CocxyColors.base))
        }
    }
}

private struct ReviewShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.blue))
                .frame(width: 88, alignment: .leading)

            Text(description)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.subtext1))

            Spacer()
        }
    }
}
