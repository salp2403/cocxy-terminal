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
        HStack(spacing: 8) {
            Label(localized("sessionReplay.title", fallback: "Session Replay"), systemImage: "record.circle")
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
                Label(localized("sessionReplay.refresh", fallback: "Refresh"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)

            Button(role: .destructive) {
                confirmDeleteAllRecordings()
            } label: {
                Label(localized("sessionReplay.deleteAll.button", fallback: "Delete All"), systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(viewModel.recordings.isEmpty)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .controlSize(.small)
                .help(localized("common.close", fallback: "Close"))
                .accessibilityLabel(localized("sessionReplay.close", fallback: "Close Session Replay"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
