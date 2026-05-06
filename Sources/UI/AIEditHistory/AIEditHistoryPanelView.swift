// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditHistoryPanelView.swift - Local timeline, diff, and revert UI.

import AppKit
import SwiftUI

struct AIEditHistoryPanelView: View {
    @ObservedObject private var viewModel: AIEditHistoryPanelViewModel
    @State private var showingRevertSheet = false
    var localizer: AppLocalizer
    let onClose: (() -> Void)?

    init(
        viewModel: AIEditHistoryPanelViewModel,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system),
        onClose: (() -> Void)? = nil
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.localizer = localizer
        self.onClose = onClose
        viewModel.updateLocalizer(localizer)
    }

    func updatedLocalizer(_ localizer: AppLocalizer) -> AIEditHistoryPanelView {
        var copy = self
        copy.localizer = localizer
        viewModel.updateLocalizer(localizer)
        return copy
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                timelineList
                    .frame(minWidth: 240, idealWidth: 280)

                detailPane
                    .frame(minWidth: 380)
            }
        }
        .glassPanelBackground()
        .onAppear {
            viewModel.perform {
                try viewModel.refresh()
            }
        }
        .sheet(isPresented: $showingRevertSheet) {
            AIEditRevertSheet(
                selectedRecord: viewModel.selectedRecord,
                fileSummaries: viewModel.selectedFileSummaries,
                localizer: localizer,
                onCancel: { showingRevertSheet = false },
                onConfirm: {
                    viewModel.perform {
                        try viewModel.revertSelected()
                    }
                    showingRevertSheet = false
                }
            )
        }
    }

    private var toolbar: some View {
        GeometryReader { proxy in
            let presentation = AdaptivePanelToolbarPresentation.resolve(width: proxy.size.width)

            HStack(spacing: 8) {
                Label(localized("aiEditHistory.title", fallback: "Edit History"), systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                Spacer(minLength: 6)

                if presentation.showsStatus {
                    AdaptivePanelToolbarStatusText(
                        text: viewModel.errorText ?? viewModel.statusText,
                        isError: viewModel.errorText != nil
                    )
                    .frame(maxWidth: presentation.usesCompactActions ? 96 : 160, alignment: .trailing)
                }

                AdaptivePanelToolbarButton(
                    title: localized("aiEditHistory.refresh", fallback: "Refresh"),
                    systemImage: "arrow.clockwise",
                    compact: presentation.usesCompactActions
                ) {
                    viewModel.perform {
                        try viewModel.refresh()
                    }
                }

                AdaptivePanelToolbarButton(
                    title: localized("aiEditHistory.revert", fallback: "Revert"),
                    systemImage: "arrow.uturn.backward",
                    compact: presentation.usesCompactActions,
                    isDisabled: viewModel.selectedRecord == nil
                ) {
                    showingRevertSheet = true
                }

                if let onClose {
                    AdaptivePanelToolbarCloseButton(
                        title: localized("aiEditHistory.close", fallback: "Close edit history"),
                        action: onClose
                    )
                }
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 10)
    }

    private var timelineList: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { viewModel.selectedRecordID },
                set: { viewModel.select(recordID: $0) }
            )) {
                ForEach(viewModel.records) { record in
                    AIEditTimelineRow(record: record)
                        .tag(Optional(record.id))
                }
            }
            .listStyle(.sidebar)

            if viewModel.records.isEmpty {
                Text(localized("aiEditHistory.status.noEdits", fallback: "No edits"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let record = viewModel.selectedRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)
                        Text(record.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.selectedFileSummaries, id: \.filePath) { summary in
                            AIEditFileSummaryRow(summary: summary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.selectedChanges, id: \.filePath) { change in
                            AIEditDiffView(change: change, localizer: localizer)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack {
                Spacer()
                Text(localized("aiEditHistory.empty.noSelection", fallback: "No edit selected"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct AIEditTimelineRow: View {
    let record: AIEditRecordPresentation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .lineLimit(1)
                Text(record.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct AIEditFileSummaryRow: View {
    let summary: AIEditFileSummary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(summary.filePath)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("+\(summary.additions)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.green)
            Text("-\(summary.deletions)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.red)
        }
        .padding(.vertical, 5)
    }
}

private struct AIEditDiffView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.designThemePalette) private var designPalette
    let change: AIEditChange
    let localizer: AppLocalizer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(change.filePath)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            HSplitView {
                diffColumn(
                    title: localizer.string("aiEditHistory.diff.before", fallback: "Before"),
                    content: change.beforeContent
                )
                diffColumn(
                    title: localizer.string("aiEditHistory.diff.after", fallback: "After"),
                    content: change.afterContent
                )
            }
            .frame(minHeight: 120)
        }
    }

    private func diffColumn(title: String, content: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(content ?? localizer.string("aiEditHistory.diff.missing", fallback: "(missing)"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(panelSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(minWidth: 160)
    }

    private var panelSurface: Color {
        Design
            .panelPalette(for: colorScheme, current: designPalette)
            .backgroundSecondary
            .resolvedColor()
    }
}

private struct AIEditRevertSheet: View {
    let selectedRecord: AIEditRecordPresentation?
    let fileSummaries: [AIEditFileSummary]
    let localizer: AppLocalizer
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("aiEditHistory.revertSheet.title", fallback: "Revert Edit?"))
                .font(.system(size: 15, weight: .semibold))

            Text(
                localized(
                    "aiEditHistory.revertSheet.message",
                    fallback: "This restores the selected local edit only if the files still match the recorded output."
                )
            )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let selectedRecord {
                Text(selectedRecord.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(fileSummaries, id: \.filePath) { summary in
                    Text(summary.filePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                }
            }

            HStack {
                Spacer()
                Button(localized("common.cancel", fallback: "Cancel"), action: onCancel)
                Button(localized("aiEditHistory.revert", fallback: "Revert"), role: .destructive, action: onConfirm)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
