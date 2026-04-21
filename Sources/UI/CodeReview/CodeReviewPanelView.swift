// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewPanelView.swift - SwiftUI container for the agent review panel.

import AppKit
import SwiftUI

struct CodeReviewPanelView: View {
    @ObservedObject var viewModel: CodeReviewPanelViewModel
    var panelWidth: CGFloat = Self.defaultPanelWidth
    var canDecreaseWidth: Bool = false
    var canIncreaseWidth: Bool = true
    var onDecreaseWidth: (() -> Void)? = nil
    var onIncreaseWidth: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    /// Forced `NSAppearance` for the translucent panel background.
    ///
    /// `nil` preserves the legacy inherit-from-window behaviour; non-nil
    /// values pin the vibrancy view so the review panel matches the rest
    /// of the chrome when the user forces a transparency theme.
    var vibrancyAppearanceOverride: NSAppearance?

    static let defaultPanelWidth: CGFloat = 640
    static let minimumPanelWidth: CGFloat = 460
    static let maximumPanelWidth: CGFloat = 1400
    static let panelResizeStep: CGFloat = 160
    private static let toolbarReservedHeight: CGFloat = 108

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            if let errorMessage = viewModel.lastErrorMessage {
                banner(message: errorMessage, kind: .error)
            }
            if let infoMessage = viewModel.lastInfoMessage {
                banner(message: infoMessage, kind: .info)
            }
            Divider()
            if !viewModel.reviewAgentSessions.isEmpty {
                CodeReviewAgentActivityView(sessions: viewModel.reviewAgentSessions)
                Divider()
            }
            if viewModel.isGitWorkflowVisible {
                CodeReviewGitWorkflowPanel(viewModel: viewModel)
                Divider()
            }

            ZStack(alignment: .bottom) {
                panelContent
                    .padding(.bottom, Self.toolbarReservedHeight)

                VStack(spacing: 0) {
                    Divider()
                    ReviewToolbarView(viewModel: viewModel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)
            .clipped()
            .layoutPriority(1)
        }
        .frame(minWidth: Self.minimumPanelWidth, maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(
                    material: .sidebar,
                    blendingMode: .behindWindow,
                    appearanceOverride: vibrancyAppearanceOverride
                )
            }
        )
        .overlay(
            ReviewKeyMonitor(
                isComposerActive: viewModel.selectedLineForComment != nil,
                onEscape: {
                    if viewModel.selectedLineForComment != nil {
                        viewModel.clearDraftCommentAnchor()
                    } else {
                        onDismiss?()
                    }
                },
                onSubmitAll: {
                    viewModel.submitComments()
                },
                onComment: {
                    viewModel.activateCommentComposerForSelection()
                },
                onNextHunk: {
                    viewModel.selectNextHunk()
                },
                onPreviousHunk: {
                    viewModel.selectPreviousHunk()
                },
                onNextFile: {
                    viewModel.nextFile()
                },
                onPreviousFile: {
                    viewModel.previousFile()
                },
                onAccept: {
                    viewModel.acceptSelectedHunk()
                },
                onReject: {
                    viewModel.rejectSelectedHunk()
                },
                onToggleDiffMode: {
                    viewModel.toggleDiffMode()
                }
            )
            .frame(width: 0, height: 0)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent code review panel")
        .alert(
            "Save editor changes?",
            isPresented: Binding(
                get: { viewModel.pendingEditorSwitch != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.cancelEditorFileSwitch()
                    }
                }
            )
        ) {
            Button("Save") {
                viewModel.saveAndSwitchEditorFile()
            }
            Button("Discard", role: .destructive) {
                viewModel.discardAndSwitchEditorFile()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelEditorFileSwitch()
            }
        } message: {
            Text("Save the current file before switching to \(viewModel.pendingEditorSwitch?.targetFilePath ?? "the selected file")?")
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        if viewModel.isLoading {
            loadingView
        } else if viewModel.currentDiffs.isEmpty {
            emptyStateView
        } else {
            HSplitView {
                fileListPane
                    .frame(minWidth: 170, idealWidth: 190, maxWidth: 220)

                VStack(spacing: 0) {
                    if let fileDiff = viewModel.selectedFileDiff {
                        selectedFileSummary(fileDiff)
                        Divider()
                    }

                    if viewModel.isEditorVisible {
                        if viewModel.isEditorExpanded {
                            CodeReviewFileEditorView(viewModel: viewModel, fillsAvailableSpace: true)
                        } else {
                            CodeReviewEditorDiffSplitView(viewModel: viewModel) {
                                diffContentView
                            }
                        }
                    } else {
                        diffContentView
                    }

                    if let target = viewModel.selectedLineForComment {
                        Divider()
                        InlineCommentView(
                            filePath: target.filePath,
                            line: target.line,
                            existingComments: viewModel.comments(for: target.filePath, line: target.line),
                            onSubmit: { text in
                                viewModel.addComment(filePath: target.filePath, line: target.line, body: text)
                            },
                            onCancel: {
                                viewModel.clearDraftCommentAnchor()
                            },
                            onRemove: { id in
                                viewModel.removeComment(id: id)
                            }
                        )
                        .padding(12)
                    }

                    if !viewModel.reviewRounds.isEmpty {
                        Divider()
                        reviewRoundsView
                    }
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)
        }
    }

    private var diffContentView: some View {
        DiffContentBridge(
            fileDiff: viewModel.selectedFileDiff,
            comments: viewModel.comments(for: viewModel.selectedFilePath ?? ""),
            selectedLineNumber: viewModel.selectedLineNumber,
            selectedHunkID: viewModel.selectedHunkID,
            onLineClicked: { filePath, line in
                viewModel.selectLine(filePath: filePath, line: line)
            },
            onSelectHunk: { hunk in
                viewModel.selectHunk(hunk)
            },
            onAcceptHunk: { hunk in
                if let fileDiff = viewModel.selectedFileDiff {
                    viewModel.accept(hunk: hunk, in: fileDiff)
                }
            },
            onRejectHunk: { hunk in
                if let fileDiff = viewModel.selectedFileDiff {
                    viewModel.reject(hunk: hunk, in: fileDiff)
                }
            }
        )
    }

    private var expandedEditorPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 24))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text("Editor focus mode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text("The diff is temporarily hidden so the inline editor can use the full review panel.")
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                .multilineTextAlignment(.center)
            Button("Show Diff") {
                viewModel.toggleEditorExpanded()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: CocxyColors.base))
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(nsColor: CocxyColors.blue))

                        Text("Agent Code Review")
                            .font(.system(size: 13, weight: .semibold))
                    }

                    if let file = viewModel.selectedFileDiff?.displayName {
                        Text(file)
                            .font(.system(size: 10))
                            .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    } else {
                        Text("Review agent-generated changes before they land")
                            .font(.system(size: 10))
                            .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        onDecreaseWidth?()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canDecreaseWidth)
                    .help("Make review panel narrower")
                    .accessibilityLabel("Make review panel narrower")

                    Text("\(Int(panelWidth.rounded())) px")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        .frame(minWidth: 54)

                    Button {
                        onIncreaseWidth?()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canIncreaseWidth)
                    .help("Make review panel wider")
                    .accessibilityLabel("Make review panel wider")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(nsColor: CocxyColors.surface0))
                )

                Button {
                    viewModel.refreshDiffs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Refresh review")
                .accessibilityLabel("Refresh review")

                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Close review panel")
                .accessibilityLabel("Close review panel")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    headerChip(
                        label: "Mode",
                        value: viewModel.diffMode.title,
                        color: CocxyColors.blue
                    )
                    headerChip(
                        label: "Files",
                        value: "\(viewModel.currentDiffs.count)",
                        color: CocxyColors.subtext0
                    )
                    if let activeSessionId = viewModel.activeSessionId {
                        headerChip(
                            label: "Session",
                            value: String(activeSessionId.prefix(8)),
                            color: CocxyColors.mauve
                        )
                    }
                    if viewModel.pendingCommentCount > 0 {
                        headerChip(
                            label: "Pending",
                            value: "\(viewModel.pendingCommentCount) comments",
                            color: CocxyColors.yellow
                        )
                    }
                    if !viewModel.reviewRounds.isEmpty {
                        headerChip(
                            label: "Rounds",
                            value: "\(viewModel.reviewRounds.count)",
                            color: CocxyColors.green
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text("Collecting agent changes…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.shield")
                .font(.system(size: 30))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text("No reviewable changes yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text("When an agent writes or edits files in this workspace, their diffs will appear here for review.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Text("Tip: use Cmd+Option+R to reopen this panel quickly.")
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            Button("Refresh Review") {
                viewModel.refreshDiffs()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Reload the current agent diff")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var reviewRoundsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Review Rounds")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(viewModel.reviewRounds.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.reviewRounds.reversed()) { round in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Round \(round.id)")
                                    .font(.system(size: 10, weight: .semibold))
                                Spacer()
                                Text(round.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 9))
                                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                            }
                            Text("\(round.comments.count) comments · \(round.diffs.count) files · \(round.baseRef.prefix(7))")
                                .font(.system(size: 10))
                                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: CocxyColors.surface0))
                        )
                    }
                }
            }
            .frame(maxHeight: 120)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var fileListPane: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Changed Files")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(viewModel.currentDiffs.count) files ready for review")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Divider()

            FileListView(
                diffs: viewModel.currentDiffs,
                commentCount: viewModel.commentCount(for:),
                selectedPath: viewModel.selectedFilePath,
                onSelect: { path in
                    viewModel.selectFile(path)
                }
            )
        }
    }

    @ViewBuilder
    private func selectedFileSummary(_ fileDiff: FileDiff) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                statusPill(for: fileDiff.status)

                VStack(alignment: .leading, spacing: 3) {
                    Text(fileDiff.displayName)
                        .font(.system(size: 12, weight: .semibold))
                    Text(fileDiff.filePath)
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if let agentName = fileDiff.agentName {
                    headerChip(label: "Agent", value: agentName, color: CocxyColors.blue)
                }
            }

            HStack(spacing: 8) {
                summaryMetric(text: "\(fileDiff.hunks.count) hunks", color: CocxyColors.subtext0)
                summaryMetric(text: "+\(fileDiff.additions)", color: CocxyColors.green)
                summaryMetric(text: "-\(fileDiff.deletions)", color: CocxyColors.red)
                let commentCount = viewModel.commentCount(for: fileDiff.filePath)
                if commentCount > 0 {
                    summaryMetric(text: "\(commentCount) comments", color: CocxyColors.yellow)
                }
                Spacer()
                Text("Click a line to anchor feedback")
                    .font(.system(size: 10))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            }

            if let note = fileDiff.reviewNote {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(nsColor: CocxyColors.yellow))
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: CocxyColors.mantle))
    }

    private enum BannerKind {
        case error
        case info

        var symbolName: String {
            switch self {
            case .error: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var tintColor: NSColor {
            switch self {
            case .error: return CocxyColors.red
            case .info: return CocxyColors.yellow
            }
        }

        var backgroundColor: NSColor {
            switch self {
            case .error: return CocxyColors.red
            case .info: return CocxyColors.yellow
            }
        }

        var accessibilityPrefix: String {
            switch self {
            case .error: return "Review error"
            case .info: return "Review notice"
            }
        }
    }

    private func banner(message: String, kind: BannerKind) -> some View {
        HStack(spacing: 8) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(nsColor: kind.tintColor))

            Text(message)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: kind.backgroundColor).opacity(0.08))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.accessibilityPrefix): \(message)")
    }

    private func headerChip(label: String, value: String, color: NSColor) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(nsColor: color))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(nsColor: color).opacity(0.10))
        )
    }

    private func summaryMetric(text: String, color: NSColor) -> some View {
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

    private func statusPill(for status: FileStatus) -> some View {
        Text(status.rawValue)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(Color(nsColor: statusColor(for: status)))
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: statusColor(for: status)).opacity(0.14))
            )
    }

    private func statusColor(for status: FileStatus) -> NSColor {
        switch status {
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

private struct CodeReviewEditorDiffSplitView<DiffContent: View>: View {
    @ObservedObject var viewModel: CodeReviewPanelViewModel
    @ViewBuilder let diffContent: DiffContent
    @State private var dragStartFraction: Double?

    var body: some View {
        GeometryReader { proxy in
            let isSideBySide = viewModel.editorSplitLayout == .sideBySide
            let available = isSideBySide ? proxy.size.width : proxy.size.height
            let handleExtent: CGFloat = 14
            let usableExtent = max(0, available - handleExtent)
            let minimumPaneExtent: CGFloat = isSideBySide ? 260 : 180
            let rawEditorExtent = usableExtent * viewModel.editorSplitFraction
            let canFitTwoMinimumPanes = usableExtent >= minimumPaneExtent * 2
            let editorExtent = canFitTwoMinimumPanes
                ? min(max(minimumPaneExtent, rawEditorExtent), usableExtent - minimumPaneExtent)
                : max(0, usableExtent * 0.5)
            let diffExtent = max(0, usableExtent - editorExtent)

            if isSideBySide {
                HStack(spacing: 0) {
                    CodeReviewFileEditorView(viewModel: viewModel, fillsAvailableSpace: true)
                        .frame(width: editorExtent)
                    splitHandle(axis: .vertical, available: usableExtent, handleExtent: handleExtent)
                    diffContent
                        .frame(width: diffExtent)
                        .clipped()
                }
            } else {
                VStack(spacing: 0) {
                    CodeReviewFileEditorView(viewModel: viewModel, fillsAvailableSpace: true)
                        .frame(height: editorExtent)
                    splitHandle(axis: .horizontal, available: usableExtent, handleExtent: handleExtent)
                    diffContent
                        .frame(height: diffExtent)
                        .clipped()
                }
            }
        }
        .frame(minHeight: 420)
    }

    private enum SplitAxis {
        case horizontal
        case vertical
    }

    private func splitHandle(axis: SplitAxis, available: CGFloat, handleExtent: CGFloat) -> some View {
        let isHorizontal = axis == .horizontal
        return ZStack {
            Rectangle()
                .fill(Color(nsColor: CocxyColors.surface0).opacity(0.78))
                .overlay(
                    Rectangle()
                        .fill(Color(nsColor: CocxyColors.surface2).opacity(0.45))
                        .frame(
                            width: isHorizontal ? nil : 1,
                            height: isHorizontal ? 1 : nil
                        )
                )
                .frame(
                    width: isHorizontal ? nil : handleExtent,
                    height: isHorizontal ? handleExtent : nil
                )

            Capsule()
                .fill(Color(nsColor: CocxyColors.blue).opacity(0.62))
                .frame(width: isHorizontal ? 58 : 4, height: isHorizontal ? 4 : 58)
                .shadow(color: Color(nsColor: CocxyColors.blue).opacity(0.24), radius: 4)
        }
        .frame(width: isHorizontal ? nil : handleExtent, height: isHorizontal ? handleExtent : nil)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartFraction == nil {
                        dragStartFraction = viewModel.editorSplitFraction
                    }
                    let delta = isHorizontal
                        ? value.translation.height / max(available, 1)
                        : value.translation.width / max(available, 1)
                    viewModel.setEditorSplitFraction((dragStartFraction ?? viewModel.editorSplitFraction) + Double(delta))
                }
                .onEnded { _ in
                    dragStartFraction = nil
                }
        )
        .accessibilityLabel(isHorizontal ? "Resize stacked editor and diff" : "Resize side-by-side editor and diff")
        .help(isHorizontal ? "Drag to resize editor and diff vertically" : "Drag to resize editor and diff horizontally")
    }
}

private struct CodeReviewFileEditorView: View {
    @ObservedObject var viewModel: CodeReviewPanelViewModel
    let fillsAvailableSpace: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "curlybraces")
                    .foregroundColor(Color(nsColor: CocxyColors.blue))

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.editorFilePath ?? "Editor")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                    Text("\(viewModel.editorLanguage) · \(lineCount) lines")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                }

                Spacer()

                Picker("Editor layout", selection: $viewModel.editorSplitLayout) {
                    ForEach(CodeReviewEditorSplitLayout.allCases) { layout in
                        Label(layout.title, systemImage: layout.systemImage)
                            .tag(layout)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 122)
                .disabled(viewModel.isEditorExpanded)
                .help("Switch between stacked and side-by-side editor/diff layout")

                HStack(spacing: 6) {
                    Button {
                        viewModel.requestEditorUndo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .help("Undo editor change")

                    Button {
                        viewModel.requestEditorRedo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .buttonStyle(.bordered)
                    .help("Redo editor change")
                }

                HStack(spacing: 6) {
                    Button {
                        viewModel.adjustEditorFontSize(by: -1)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .buttonStyle(.bordered)
                    .help("Decrease editor font size")

                    Text("\(Int(viewModel.editorFontSize))pt")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        .frame(width: 34)

                    Button {
                        viewModel.adjustEditorFontSize(by: 1)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .buttonStyle(.bordered)
                    .help("Increase editor font size")
                }

                HStack(spacing: 6) {
                    Button {
                        viewModel.adjustEditorSplitFraction(by: -0.08)
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isEditorExpanded)
                    .help("Give the diff more room")

                    Button {
                        viewModel.adjustEditorSplitFraction(by: 0.08)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isEditorExpanded)
                    .help("Give the editor more room")

                    Button {
                        viewModel.toggleEditorExpanded()
                    } label: {
                        Label(
                            viewModel.isEditorExpanded ? "Restore" : "Focus",
                            systemImage: viewModel.isEditorExpanded
                                ? "rectangle.compress.vertical"
                                : "rectangle.expand.vertical"
                        )
                    }
                    .buttonStyle(.bordered)
                    .help(viewModel.isEditorExpanded ? "Restore diff view" : "Give the editor the full panel")
                }

                if viewModel.isEditorDirty {
                    Text("modified")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.yellow))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: CocxyColors.yellow).opacity(0.12))
                        )
                }

                Button("Reload") {
                    viewModel.reloadEditorContent()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    viewModel.saveEditorContent()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isEditorDirty)

                Button {
                    viewModel.closeEditor()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close editor")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: CocxyColors.surface0).opacity(0.9))

            if let error = viewModel.editorErrorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: CocxyColors.red))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: CocxyColors.red).opacity(0.10))
            }

            CodeReviewSyntaxTextEditor(
                text: $viewModel.editorContent,
                language: viewModel.editorLanguage,
                fontSize: CGFloat(viewModel.editorFontSize),
                commandToken: viewModel.editorCommandToken
            )
                .frame(minHeight: 220)
                .frame(height: fillsAvailableSpace || viewModel.isEditorExpanded ? nil : CGFloat(viewModel.editorHeight))
                .frame(maxHeight: fillsAvailableSpace || viewModel.isEditorExpanded ? .infinity : nil)
                .layoutPriority(viewModel.isEditorExpanded ? 3 : 1)
                .accessibilityLabel("Code review inline editor")
        }
        .background(Color(nsColor: CocxyColors.base))
        .layoutPriority(viewModel.isEditorExpanded ? 3 : 1)
    }

    private var lineCount: Int {
        viewModel.editorContent
            .split(separator: "\n", omittingEmptySubsequences: false)
            .count
    }
}

@MainActor
private struct ReviewKeyMonitor: NSViewRepresentable {
    let isComposerActive: Bool
    let onEscape: () -> Void
    let onSubmitAll: () -> Void
    let onComment: () -> Void
    let onNextHunk: () -> Void
    let onPreviousHunk: () -> Void
    let onNextFile: () -> Void
    let onPreviousFile: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void
    let onToggleDiffMode: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    @MainActor
    final class Coordinator {
        var parent: ReviewKeyMonitor
        var monitor: Any?

        init(parent: ReviewKeyMonitor) {
            self.parent = parent
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        func handle(_ event: NSEvent) -> NSEvent? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command], event.keyCode == 36 {
                parent.onSubmitAll()
                return nil
            }

            if event.keyCode == 53 {
                parent.onEscape()
                return nil
            }

            guard let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1 else {
                return event
            }

            if parent.isComposerActive {
                return event
            }

            switch chars {
            case "j":
                parent.onNextHunk()
                return nil
            case "k":
                parent.onPreviousHunk()
                return nil
            case "n":
                parent.onNextFile()
                return nil
            case "p":
                parent.onPreviousFile()
                return nil
            case "c":
                parent.onComment()
                return nil
            case "a":
                parent.onAccept()
                return nil
            case "r":
                parent.onReject()
                return nil
            case "d":
                parent.onToggleDiffMode()
                return nil
            default:
                return event
            }
        }
    }
}
