// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ReviewToolbarView.swift - Bottom toolbar for the review panel.

import AppKit
import SwiftUI

struct ReviewToolbarView: View {
    @ObservedObject var viewModel: CodeReviewPanelViewModel
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        VStack(spacing: 8) {
            mergeBannerStack
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    stat(
                        text: localizedCount(
                            "codeReview.toolbar.stat.files",
                            fallback: "%d files",
                            count: viewModel.currentDiffs.count
                        ),
                        color: CocxyColors.blue
                    )
                    stat(text: "+\(totalAdditions)", color: CocxyColors.green)
                    stat(text: "-\(totalDeletions)", color: CocxyColors.red)
                    if viewModel.pendingCommentCount > 0 {
                        stat(
                            text: localizedCount(
                                "codeReview.toolbar.stat.comments",
                                fallback: "%d comments",
                                count: viewModel.pendingCommentCount
                            ),
                            color: CocxyColors.yellow
                        )
                    }
                    if !viewModel.reviewRounds.isEmpty {
                        stat(
                            text: localizedCount(
                                "codeReview.toolbar.stat.rounds",
                                fallback: "%d rounds",
                                count: viewModel.reviewRounds.count
                            ),
                            color: CocxyColors.mauve
                        )
                    }
                    if let gitStatus = viewModel.gitStatus {
                        stat(text: gitStatus.summary, color: CocxyColors.sky)
                    }
                    if !viewModel.reviewAgentSessions.isEmpty {
                        stat(
                            text: localizedCount(
                                "codeReview.toolbar.stat.agents",
                                fallback: "%d agents",
                                count: viewModel.reviewAgentSessions.count
                            ),
                            color: CocxyColors.blue
                        )
                    }
                    if viewModel.reviewSubagentCount > 0 {
                        stat(
                            text: localizedCount(
                                "codeReview.toolbar.stat.subagents",
                                fallback: "%d subagents",
                                count: viewModel.reviewSubagentCount
                            ),
                            color: CocxyColors.mauve
                        )
                    }
                    if viewModel.reviewTouchedFileCount > 0 {
                        stat(
                            text: localizedCount(
                                "codeReview.toolbar.stat.touched",
                                fallback: "%d touched",
                                count: viewModel.reviewTouchedFileCount
                            ),
                            color: CocxyColors.green
                        )
                    }
                    if viewModel.reviewConflictCount > 0 {
                        stat(
                            text: localizedCount(
                                "codeReview.toolbar.stat.conflicts",
                                fallback: "%d conflicts",
                                count: viewModel.reviewConflictCount
                            ),
                            color: CocxyColors.red
                        )
                    }
                    ReviewKeyboardHintsButton(localizer: localizer)
                }
            }
            .frame(height: 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Picker(
                        localized("codeReview.toolbar.diffMode", fallback: "Diff Mode"),
                        selection: $viewModel.diffMode
                    ) {
                        ForEach(DiffMode.allCases, id: \.self) { mode in
                            Text(mode.localizedTitle(using: localizer)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.diffMode) { _, _ in
                        viewModel.refreshDiffs()
                    }
                    .accessibilityHint(
                        localized(
                            "codeReview.toolbar.diffMode.hint",
                            fallback: "Switch the review comparison mode"
                        )
                    )

                    Button {
                        viewModel.refreshDiffs()
                    } label: {
                        Label(
                            localized("codeReview.toolbar.refresh", fallback: "Refresh"),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(
                        localized(
                            "codeReview.toolbar.refresh.hint",
                            fallback: "Reload the current review diff"
                        )
                    )

                    Button {
                        viewModel.openSelectedFileInEditor()
                    } label: {
                        Label(
                            localized("codeReview.toolbar.editFile", fallback: "Edit File"),
                            systemImage: "curlybraces"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.selectedFileDiff == nil)
                    .accessibilityHint(
                        localized(
                            "codeReview.toolbar.editFile.hint",
                            fallback: "Open the selected file in the inline review editor"
                        )
                    )

                    Button {
                        viewModel.toggleGitWorkflowVisibility()
                    } label: {
                        Label(
                            viewModel.isGitWorkflowVisible
                                ? localized("codeReview.toolbar.hideGit", fallback: "Hide Git")
                                : localized("codeReview.toolbar.git", fallback: "Git"),
                            systemImage: "arrow.triangle.branch"
                        )
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(
                        localized(
                            "codeReview.toolbar.git.hint",
                            fallback: "Show branch, commit, and push controls inside the review panel"
                        )
                    )

                    if viewModel.pendingCommentCount > 0 {
                        Button(role: .destructive) {
                            viewModel.discardPendingComments()
                        } label: {
                            Label(
                                localized("codeReview.toolbar.discardDrafts", fallback: "Discard Drafts"),
                                systemImage: "trash"
                            )
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint(
                            localized(
                                "codeReview.toolbar.discardDrafts.hint",
                                fallback: "Clear all pending inline comments"
                            )
                        )
                    }

                    if viewModel.pendingSuggestionCount > 0 {
                        Button {
                            viewModel.applyPendingSuggestions()
                        } label: {
                            Label(
                                localizedSuggestionApplyLabel(count: viewModel.pendingSuggestionCount),
                                systemImage: "checkmark.rectangle.stack"
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isMergingPullRequest)
                        .accessibilityHint(
                            localized(
                                "codeReview.toolbar.applySuggestions.hint",
                                fallback: "Apply pending suggestion blocks to local files after conflict checks"
                            )
                        )
                    }

                    if let prNumber = viewModel.activePullRequestNumber {
                        mergeButton(prNumber: prNumber)
                    }

                    Button {
                        viewModel.submitComments()
                    } label: {
                        Label(
                            viewModel.pendingCommentCount == 0
                                ? localized("codeReview.toolbar.submit", fallback: "Submit")
                                : localizedCount(
                                    "codeReview.toolbar.submitCount",
                                    fallback: "Submit %d",
                                    count: viewModel.pendingCommentCount
                                ),
                            systemImage: "paperplane.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.pendingCommentCount == 0 || viewModel.isMergingPullRequest)
                    .accessibilityHint(
                        localized(
                            "codeReview.toolbar.submit.hint",
                            fallback: "Send all pending comments back to the originating agent"
                        )
                    )
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

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }

    private func localizedCount(_ key: String, fallback: String, count: Int) -> String {
        String(format: localized(key, fallback: fallback), count)
    }

    private func localizedSuggestionApplyLabel(count: Int) -> String {
        if count == 1 {
            return localized("codeReview.toolbar.applySuggestions.one", fallback: "Apply suggestion")
        }
        return localizedCount(
            "codeReview.toolbar.applySuggestions.many",
            fallback: "Apply %d suggestions",
            count: count
        )
    }

    // MARK: - Merge banners (v0.1.86)

    /// Stacks the dedicated merge info/error banners above the stats
    /// row. Kept in their own channel — separate from
    /// `lastErrorMessage` / `lastInfoMessage` — so the merge feedback
    /// does not get overwritten by the next git workflow notice.
    /// Hidden entirely when both messages are nil so the toolbar
    /// stays compact during regular review work.
    @ViewBuilder
    private var mergeBannerStack: some View {
        if viewModel.pullRequestMergeErrorMessage != nil
            || viewModel.pullRequestMergeInfoMessage != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let info = viewModel.pullRequestMergeInfoMessage {
                    mergeBanner(text: info, kind: .info)
                }
                if let error = viewModel.pullRequestMergeErrorMessage {
                    mergeBanner(text: error, kind: .error)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private enum MergeBannerKind {
        case info
        case error

        var iconName: String {
            switch self {
            case .info: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }

        var tint: NSColor {
            switch self {
            case .info: return CocxyColors.green
            case .error: return CocxyColors.red
            }
        }

        var accessibilityPrefix: String {
            switch self {
            case .info: return "Merge information"
            case .error: return "Merge error"
            }
        }

        func localizedAccessibilityPrefix(using localizer: AppLocalizer) -> String {
            switch self {
            case .info:
                return localizer.string(
                    "codeReview.toolbar.merge.info",
                    fallback: accessibilityPrefix
                )
            case .error:
                return localizer.string(
                    "codeReview.toolbar.merge.error",
                    fallback: accessibilityPrefix
                )
            }
        }
    }

    private func mergeBanner(text: String, kind: MergeBannerKind) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: kind.iconName)
                .foregroundColor(Color(nsColor: kind.tint))
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: kind.tint).opacity(0.10))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.localizedAccessibilityPrefix(using: localizer)): \(text)")
    }

    // MARK: - Merge button (v0.1.86)

    /// Renders the "Merge PR #N" button with a status chip describing
    /// the current mergeability state. The button is disabled when
    /// the cached snapshot says we cannot merge or while another
    /// merge is in flight; tooltip carries the explicit reason.
    private func mergeButton(prNumber: Int) -> some View {
        let mergeability = viewModel.activePullRequestMergeability
        let canMerge = mergeability?.canMerge ?? false
        let canStartMergeAction = viewModel.canStartPullRequestMergeAction
        let canEnableAutoMerge = viewModel.activePullRequestCanEnableAutoMerge
        let isMerging = viewModel.isMergingPullRequest
        let chipKind = mergeability?.chipKind ?? .pending
        let tooltip = mergeButtonTooltip(
            canMerge: canMerge,
            canEnableAutoMerge: canEnableAutoMerge,
            mergeability: mergeability,
            isMerging: isMerging
        )
        return HStack(spacing: 6) {
            mergeStatusChip(kind: chipKind)
            Button {
                presentMergeActionSheet(prNumber: prNumber)
            } label: {
                Label {
                    Text(
                        localizedCount(
                            "codeReview.toolbar.merge.button",
                            fallback: "Merge PR #%d",
                            count: prNumber
                        )
                    )
                } icon: {
                    if isMerging {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.merge")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(nsColor: CocxyColors.green))
            .disabled(!canStartMergeAction || isMerging)
            .help(tooltip)
            .accessibilityHint(tooltip)
        }
    }

    private func mergeStatusChip(kind: GitHubMergeability.ChipKind) -> some View {
        let (label, color): (String, NSColor) = {
            switch kind {
            case .ready:
                return (
                    localized("codeReview.toolbar.merge.status.ready", fallback: "Ready"),
                    CocxyColors.green
                )
            case .pending:
                return (
                    localized("codeReview.toolbar.merge.status.pending", fallback: "Pending"),
                    CocxyColors.yellow
                )
            case .blocked:
                return (
                    localized("codeReview.toolbar.merge.status.blocked", fallback: "Blocked"),
                    CocxyColors.red
                )
            case .conflicting:
                return (
                    localized("codeReview.toolbar.merge.status.conflicts", fallback: "Conflicts"),
                    CocxyColors.red
                )
            case .merged:
                return (
                    localized("codeReview.toolbar.merge.status.merged", fallback: "Merged"),
                    CocxyColors.mauve
                )
            case .closed:
                return (
                    localized("codeReview.toolbar.merge.status.closed", fallback: "Closed"),
                    CocxyColors.overlay1
                )
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(Color(nsColor: color))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(nsColor: color).opacity(0.14))
            )
            .accessibilityLabel(
                String(
                    format: localized(
                        "codeReview.toolbar.merge.status.accessibility",
                        fallback: "Merge status: %@"
                    ),
                    label
                )
            )
    }

    private func mergeButtonTooltip(
        canMerge: Bool,
        canEnableAutoMerge: Bool,
        mergeability: GitHubMergeability?,
        isMerging: Bool
    ) -> String {
        if isMerging {
            return localized(
                "codeReview.toolbar.merge.tooltip.inProgress",
                fallback: "Merging in progress..."
            )
        }
        if canMerge {
            return localized(
                "codeReview.toolbar.merge.tooltip.ready",
                fallback: "Merge this pull request via gh."
            )
        }
        if canEnableAutoMerge {
            return localized(
                "codeReview.toolbar.merge.tooltip.autoMerge",
                fallback: "Enable auto-merge once requirements pass."
            )
        }
        if let mergeability,
           let reason = mergeability.reasonIfBlocked,
           !reason.isEmpty {
            return reason
        }
        return localized(
            "codeReview.toolbar.merge.tooltip.pending",
            fallback: "Mergeability is being computed."
        )
    }

    private func presentMergeActionSheet(prNumber: Int) {
        guard let decision = MergePullRequestActionSheet.present(
            pullRequestNumber: prNumber,
            localizer: localizer
        ) else { return }
        viewModel.requestMergePullRequest(
            method: decision.method,
            deleteBranch: decision.deleteBranch
        )
    }
}

private struct ReviewKeyboardHintsButton: View {
    @State private var isShowingPopover = false
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
        }
        .buttonStyle(.plain)
        .help(localized("codeReview.toolbar.shortcuts.help", fallback: "Review shortcuts"))
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text(localized("codeReview.toolbar.shortcuts.title", fallback: "Review Shortcuts"))
                    .font(.system(size: 13, weight: .bold))

                ReviewShortcutRow(
                    keys: "j / k",
                    description: localized(
                        "codeReview.toolbar.shortcuts.nextHunk",
                        fallback: "Next / previous hunk"
                    )
                )
                ReviewShortcutRow(
                    keys: "n / p",
                    description: localized(
                        "codeReview.toolbar.shortcuts.nextFile",
                        fallback: "Next / previous file"
                    )
                )
                ReviewShortcutRow(
                    keys: "c",
                    description: localized(
                        "codeReview.toolbar.shortcuts.comment",
                        fallback: "Comment current line"
                    )
                )
                ReviewShortcutRow(
                    keys: "a / r",
                    description: localized(
                        "codeReview.toolbar.shortcuts.acceptReject",
                        fallback: "Accept / reject hunk"
                    )
                )
                ReviewShortcutRow(
                    keys: "d",
                    description: localized(
                        "codeReview.toolbar.shortcuts.diffMode",
                        fallback: "Cycle diff mode"
                    )
                )
                ReviewShortcutRow(
                    keys: "Cmd+Enter",
                    description: localized(
                        "codeReview.toolbar.shortcuts.submitAll",
                        fallback: "Submit all comments"
                    )
                )
                ReviewShortcutRow(
                    keys: "Esc",
                    description: localized(
                        "codeReview.toolbar.shortcuts.cancel",
                        fallback: "Cancel comment / close panel"
                    )
                )
            }
            .padding(16)
            .frame(width: 250)
            .glassPanelBackground()
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
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
