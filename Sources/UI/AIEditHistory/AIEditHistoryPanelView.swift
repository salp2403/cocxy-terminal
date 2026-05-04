// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditHistoryPanelView.swift - Local timeline, diff, and revert UI.

import AppKit
import SwiftUI

struct AIEditHistoryPanelView: View {
    @StateObject private var viewModel: AIEditHistoryPanelViewModel
    @State private var showingRevertSheet = false
    let onClose: (() -> Void)?

    init(viewModel: AIEditHistoryPanelViewModel, onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onClose = onClose
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
        HStack(spacing: 8) {
            Label("Edit History", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let errorText = viewModel.errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else {
                Text(viewModel.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                viewModel.perform {
                    try viewModel.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)

            Button {
                showingRevertSheet = true
            } label: {
                Label("Revert", systemImage: "arrow.uturn.backward")
            }
            .controlSize(.small)
            .disabled(viewModel.selectedRecord == nil)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .controlSize(.small)
                .help("Close")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
                Text("No edits")
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
                            AIEditDiffView(change: change)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack {
                Spacer()
                Text("No edit selected")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
    let change: AIEditChange

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(change.filePath)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            HSplitView {
                diffColumn(title: "Before", content: change.beforeContent)
                diffColumn(title: "After", content: change.afterContent)
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
                Text(content ?? "(missing)")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: CocxyColors.surface0))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(minWidth: 160)
    }
}

private struct AIEditRevertSheet: View {
    let selectedRecord: AIEditRecordPresentation?
    let fileSummaries: [AIEditFileSummary]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Revert Edit?")
                .font(.system(size: 15, weight: .semibold))

            Text("This restores the selected local edit only if the files still match the recorded output.")
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
                Button("Cancel", action: onCancel)
                Button("Revert", role: .destructive, action: onConfirm)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}
