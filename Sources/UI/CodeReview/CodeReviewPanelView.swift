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

    static let defaultPanelWidth: CGFloat = 640
    static let minimumPanelWidth: CGFloat = 460
    static let maximumPanelWidth: CGFloat = 980
    static let panelResizeStep: CGFloat = 120

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
            }

            Divider()
            ReviewToolbarView(viewModel: viewModel)
        }
        .frame(minWidth: Self.minimumPanelWidth, maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
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
                selectedPath: $viewModel.selectedFilePath
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
