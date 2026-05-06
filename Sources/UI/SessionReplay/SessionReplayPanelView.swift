// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionReplayPanelView.swift - Local session recording library and replay controls.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SessionReplayPanelView: View {
    @ObservedObject private var viewModel: SessionReplayPanelViewModel
    var localizer: AppLocalizer
    let onClose: (() -> Void)?

    init(
        viewModel: SessionReplayPanelViewModel,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system),
        onClose: (() -> Void)? = nil
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.localizer = localizer
        self.onClose = onClose
        viewModel.updateLocalizer(localizer)
    }

    func updatedLocalizer(_ localizer: AppLocalizer) -> SessionReplayPanelView {
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
                recordingList
                    .frame(minWidth: 240, idealWidth: 280)

                detailPane
                    .frame(minWidth: 360)
            }
        }
        .glassPanelBackground()
        .onAppear {
            viewModel.perform {
                try viewModel.refresh()
            }
        }
    }

    private var toolbar: some View {
        GeometryReader { proxy in
            let presentation = AdaptivePanelToolbarPresentation.resolve(width: proxy.size.width)

            HStack(spacing: 8) {
                Label(localized("sessionReplay.title", fallback: "Session Replay"), systemImage: "record.circle")
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
                    title: localized("sessionReplay.refresh", fallback: "Refresh"),
                    systemImage: "arrow.clockwise",
                    compact: presentation.usesCompactActions
                ) {
                    viewModel.perform {
                        try viewModel.refresh()
                    }
                }

                AdaptivePanelToolbarButton(
                    title: localized("sessionReplay.deleteAll.button", fallback: "Delete All"),
                    systemImage: "trash",
                    compact: presentation.usesCompactActions,
                    isDisabled: viewModel.recordings.isEmpty
                ) {
                    confirmDeleteAllRecordings()
                }

                if let onClose {
                    AdaptivePanelToolbarCloseButton(
                        title: localized("sessionReplay.close", fallback: "Close Session Replay"),
                        action: onClose
                    )
                }
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 10)
    }

    private func confirmDeleteAllRecordings() {
        let alert = NSAlert()
        let copy = Self.localizedDeleteAllRecordingsCopy(localizer: localizer)
        alert.messageText = copy.messageText
        alert.informativeText = copy.informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: copy.primaryButton)
        alert.addButton(withTitle: copy.secondaryButton)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        viewModel.perform {
            try viewModel.deleteAll()
        }
    }

    static func localizedDeleteAllRecordingsCopy(localizer: AppLocalizer) -> AppAlertCopy {
        AppAlertCopy(
            messageText: localizer.string("sessionReplay.deleteAll.title", fallback: "Delete All Recordings?"),
            informativeText: localizer.string(
                "sessionReplay.deleteAll.message",
                fallback: "This removes every local Session Replay recording from this Mac."
            ),
            primaryButton: localizer.string("sessionReplay.deleteAll.button", fallback: "Delete All"),
            secondaryButton: localizer.string("common.cancel", fallback: "Cancel")
        )
    }

    private var recordingList: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { viewModel.selectedRecordingID },
                set: { viewModel.select(recordingID: $0) }
            )) {
                ForEach(viewModel.recordings) { recording in
                    RecordingRow(recording: recording)
                        .tag(Optional(recording.id))
                }
            }
            .listStyle(.sidebar)

            if viewModel.recordings.isEmpty {
                Text(localized("sessionReplay.status.noRecordings", fallback: "No recordings"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let recording = viewModel.selectedRecording {
            VStack(alignment: .leading, spacing: 0) {
                replayControls(for: recording)
                Divider()
                HSplitView {
                    searchPane
                        .frame(minWidth: 220)
                    bookmarksPane(recording.bookmarks)
                        .frame(minWidth: 200)
                }
            }
        } else {
            VStack {
                Spacer()
                Text(localized("sessionReplay.empty.noSelection", fallback: "No recording selected"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func replayControls(for recording: SessionReplayRecordingPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(recording.durationText) - \(recording.byteCountText)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Picker("", selection: $viewModel.speedMultiplier) {
                    Text("0.5x").tag(Float(0.5))
                    Text("1x").tag(Float(1))
                    Text("2x").tag(Float(2))
                    Text("5x").tag(Float(5))
                }
                .pickerStyle(.segmented)
                .frame(width: 184)

                Button {
                    viewModel.perform {
                        try viewModel.replaySelected()
                    }
                } label: {
                    Label(localized("sessionReplay.replay", fallback: "Replay"), systemImage: "play.fill")
                }
                .controlSize(.small)
                .disabled(!viewModel.canReplay)
            }

            HStack(spacing: 8) {
                Text(viewModel.seekText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { viewModel.seekSeconds },
                        set: { viewModel.seekSeconds = $0 }
                    ),
                    in: 0...max(viewModel.durationSeconds, 0.001)
                )

                Text(recording.durationText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            }

            HStack(spacing: 8) {
                TextField(
                    localized("sessionReplay.bookmark.placeholder", fallback: "Bookmark label"),
                    text: $viewModel.bookmarkLabel
                )
                    .textFieldStyle(.roundedBorder)

                Button {
                    viewModel.perform {
                        try viewModel.addBookmarkAtSeek()
                    }
                } label: {
                    Label(localized("sessionReplay.bookmark", fallback: "Bookmark"), systemImage: "bookmark")
                }
                .controlSize(.small)

                Button {
                    exportRecording(recording)
                } label: {
                    Label(localized("sessionReplay.export", fallback: "Export"), systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    viewModel.perform {
                        try viewModel.deleteSelected()
                    }
                } label: {
                    Label(localized("common.delete", fallback: "Delete"), systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    private func exportRecording(_ recording: SessionReplayRecordingPresentation) {
        let panel = NSSavePanel()
        let copy = Self.localizedExportPanelCopy(localizer: localizer)
        panel.title = copy.title
        panel.message = copy.message
        panel.prompt = copy.prompt
        panel.allowedContentTypes = [UTType(filenameExtension: "cast") ?? .data]
        panel.nameFieldStringValue = Self.safeExportFilename(for: recording.title)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.perform {
            try viewModel.exportSelected(to: url)
        }
    }

    private static func safeExportFilename(for title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:")
            .union(.newlines)
            .union(.controlCharacters)
        let safeStem = title
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(safeStem.isEmpty ? "session-replay" : safeStem).cast"
    }

    static func localizedExportPanelCopy(localizer: AppLocalizer) -> AppFilePanelCopy {
        AppFilePanelCopy(
            title: localizer.string("sessionReplay.exportPanel.title", fallback: "Export Session Replay"),
            message: localizer.string(
                "sessionReplay.exportPanel.message",
                fallback: "Choose where to save this recording."
            ),
            prompt: localizer.string("common.export", fallback: "Export")
        )
    }

    private var searchPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(
                    localized("sessionReplay.search.placeholder", fallback: "Search recording"),
                    text: $viewModel.searchQuery
                )
                    .textFieldStyle(.roundedBorder)
                Button {
                    viewModel.perform {
                        try viewModel.searchSelectedRecording()
                    }
                } label: {
                    Label(localized("sessionReplay.search", fallback: "Search"), systemImage: "magnifyingglass")
                }
                .controlSize(.small)
            }
            .padding([.top, .horizontal], 10)

            List(viewModel.searchMatches) { match in
                Button {
                    viewModel.jumpToSearchMatch(match)
                } label: {
                    MatchRow(match: match)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func bookmarksPane(
        _ bookmarks: [SessionReplayBookmarkPresentation]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("sessionReplay.bookmarks", fallback: "Bookmarks"))
                .font(.system(size: 12, weight: .semibold))
                .padding([.top, .horizontal], 10)

            List(bookmarks) { bookmark in
                Button {
                    viewModel.jumpToBookmark(bookmark)
                } label: {
                    BookmarkRow(bookmark: bookmark)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct RecordingRow: View {
    let recording: SessionReplayRecordingPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            HStack {
                Text(recording.durationText)
                Text(recording.byteCountText)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct MatchRow: View {
    let match: SessionReplaySearchMatchPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(match.offsetText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(match.snippet)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

private struct BookmarkRow: View {
    let bookmark: SessionReplayBookmarkPresentation

    var body: some View {
        HStack(spacing: 8) {
            Text(bookmark.offsetText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(bookmark.label)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
    }
}
