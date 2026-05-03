// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionReplayPanelViewModel.swift - Presentation state for local session recordings.

import Combine
import Foundation

struct SessionReplayBookmarkPresentation: Identifiable, Equatable {
    let id: UUID
    let offsetNs: UInt64
    let offsetText: String
    let label: String
}

struct SessionReplayRecordingPresentation: Identifiable, Equatable {
    let id: UUID
    let title: String
    let createdAt: Date
    let durationNs: UInt64
    let durationText: String
    let byteCountText: String
    let bookmarks: [SessionReplayBookmarkPresentation]
}

struct SessionReplaySearchMatchPresentation: Identifiable, Equatable {
    let id: String
    let recordingID: UUID
    let offsetNs: UInt64
    let offsetText: String
    let snippet: String
}

enum SessionReplayPanelError: Error, Equatable, LocalizedError {
    case noSelection
    case replayDisabled
    case playbackUnavailable
    case targetSurfaceUnavailable

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "No session replay recording is selected."
        case .replayDisabled:
            return "Session Replay is disabled in preferences."
        case .playbackUnavailable:
            return "Session Replay playback is unavailable for this terminal engine."
        case .targetSurfaceUnavailable:
            return "No terminal surface is available for replay."
        }
    }
}

@MainActor
final class SessionReplayPanelViewModel: ObservableObject {
    @Published private(set) var recordings: [SessionReplayRecordingPresentation] = []
    @Published var selectedRecordingID: UUID?
    @Published var searchQuery = ""
    @Published private(set) var searchMatches: [SessionReplaySearchMatchPresentation] = []
    @Published var seekNs: UInt64 = 0
    @Published var speedMultiplier: Float = 1
    @Published var bookmarkLabel = ""
    @Published private(set) var statusText = "No recordings"
    @Published private(set) var errorText: String?

    let config: SessionReplayConfig

    private let store: SessionReplayStore
    private let playback: (any SessionReplayPlaybackControlling)?
    private let targetSurfaceProvider: () -> SurfaceID?

    var selectedRecording: SessionReplayRecordingPresentation? {
        guard let selectedRecordingID else { return nil }
        return recordings.first { $0.id == selectedRecordingID }
    }

    var selectedDurationNs: UInt64 {
        selectedRecording?.durationNs ?? 0
    }

    var seekText: String {
        Self.formatOffset(seekNs)
    }

    var seekSeconds: Double {
        get { Double(seekNs) / 1_000_000_000 }
        set {
            let durationSeconds = Double(selectedDurationNs) / 1_000_000_000
            let clamped = min(max(0, newValue), max(0, durationSeconds))
            seekNs = UInt64(clamped * 1_000_000_000)
        }
    }

    var durationSeconds: Double {
        Double(selectedDurationNs) / 1_000_000_000
    }

    var canReplay: Bool {
        config.enabled && playback != nil && selectedRecordingID != nil
    }

    init(
        config: SessionReplayConfig,
        store: SessionReplayStore = SessionReplayStore(),
        playback: (any SessionReplayPlaybackControlling)?,
        targetSurfaceProvider: @escaping () -> SurfaceID?
    ) {
        self.config = config
        self.store = store
        self.playback = playback
        self.targetSurfaceProvider = targetSurfaceProvider
    }

    func refresh() throws {
        let previousSelection = selectedRecordingID
        let loaded = try store.listRecordings()
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
        recordings = loaded.map(Self.presentation)

        if let previousSelection,
           recordings.contains(where: { $0.id == previousSelection }) {
            selectedRecordingID = previousSelection
        } else {
            selectedRecordingID = recordings.first?.id
            seekNs = 0
            searchMatches = []
        }

        if let selectedRecording, seekNs > selectedRecording.durationNs {
            seekNs = selectedRecording.durationNs
        }

        let count = recordings.count
        if count == 0 {
            statusText = "No recordings"
        } else {
            statusText = count == 1 ? "1 recording" : "\(count) recordings"
        }
        errorText = nil
    }

    func select(recordingID: UUID?) {
        guard selectedRecordingID != recordingID else { return }
        selectedRecordingID = recordingID
        seekNs = 0
        searchMatches = []
    }

    func searchSelectedRecording() throws {
        guard let recordingID = selectedRecordingID else {
            throw SessionReplayPanelError.noSelection
        }
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchMatches = []
            statusText = "Search cleared"
            errorText = nil
            return
        }

        searchMatches = try store.search(recordingID: recordingID, query: trimmedQuery)
            .map(Self.searchPresentation)
        statusText = searchMatches.count == 1 ? "1 match" : "\(searchMatches.count) matches"
        errorText = nil
    }

    func jumpToSearchMatch(_ match: SessionReplaySearchMatchPresentation) {
        guard match.recordingID == selectedRecordingID else { return }
        seekNs = min(match.offsetNs, selectedDurationNs)
    }

    func jumpToBookmark(_ bookmark: SessionReplayBookmarkPresentation) {
        seekNs = min(bookmark.offsetNs, selectedDurationNs)
    }

    func addBookmarkAtSeek() throws {
        guard let recordingID = selectedRecordingID else {
            throw SessionReplayPanelError.noSelection
        }
        _ = try store.addBookmark(
            recordingID: recordingID,
            offsetNs: seekNs,
            label: bookmarkLabel
        )
        bookmarkLabel = ""
        try refresh()
        statusText = "Bookmark added"
    }

    func exportSelected(to destinationURL: URL) throws {
        guard let recordingID = selectedRecordingID else {
            throw SessionReplayPanelError.noSelection
        }
        try store.exportCast(recordingID: recordingID, to: destinationURL)
        statusText = "Exported \(destinationURL.lastPathComponent)"
        errorText = nil
    }

    func deleteSelected() throws {
        guard let recordingID = selectedRecordingID else {
            throw SessionReplayPanelError.noSelection
        }
        try store.deleteRecording(id: recordingID)
        try refresh()
        statusText = recordings.isEmpty ? "No recordings" : statusText
    }

    func replaySelected() throws {
        guard config.enabled else {
            throw SessionReplayPanelError.replayDisabled
        }
        guard let selectedRecordingID, let selectedRecording else {
            throw SessionReplayPanelError.noSelection
        }
        guard let playback else {
            throw SessionReplayPanelError.playbackUnavailable
        }
        guard let targetSurface = targetSurfaceProvider() else {
            throw SessionReplayPanelError.targetSurfaceUnavailable
        }

        let speed = normalizedSpeedMultiplier()
        try playback.replay(
            recordingID: selectedRecordingID,
            to: targetSurface,
            seekNs: min(seekNs, selectedRecording.durationNs),
            speedMultiplier: speed
        )
        statusText = "Replaying \(selectedRecording.title) at \(Self.formatSpeed(speed))x"
        errorText = nil
    }

    func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            errorText = error.localizedDescription
            statusText = "Session Replay action failed"
        }
    }

    private func normalizedSpeedMultiplier() -> Float {
        guard speedMultiplier > 0 else { return 1 }
        return min(max(speedMultiplier, 0.5), 5)
    }

    private static func presentation(
        for recording: SessionReplayRecording
    ) -> SessionReplayRecordingPresentation {
        SessionReplayRecordingPresentation(
            id: recording.id,
            title: recording.title,
            createdAt: recording.createdAt,
            durationNs: recording.durationNs,
            durationText: formatOffset(recording.durationNs),
            byteCountText: formatBytes(recording.byteCount),
            bookmarks: recording.bookmarks.map { bookmark in
                SessionReplayBookmarkPresentation(
                    id: bookmark.id,
                    offsetNs: bookmark.offsetNs,
                    offsetText: formatOffset(bookmark.offsetNs),
                    label: bookmark.label
                )
            }
        )
    }

    private static func searchPresentation(
        for match: SessionReplaySearchMatch
    ) -> SessionReplaySearchMatchPresentation {
        let snippetKey = String(match.snippet.hashValue)
        return SessionReplaySearchMatchPresentation(
            id: "\(match.recordingID.uuidString)-\(match.offsetNs)-\(snippetKey)",
            recordingID: match.recordingID,
            offsetNs: match.offsetNs,
            offsetText: formatOffset(match.offsetNs),
            snippet: match.snippet
        )
    }

    static func formatOffset(_ nanoseconds: UInt64) -> String {
        let totalMilliseconds = nanoseconds / 1_000_000
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1_000
        let milliseconds = totalMilliseconds % 1_000

        if hours > 0 {
            return String(format: "%02llu:%02llu:%02llu.%03llu", hours, minutes, seconds, milliseconds)
        }
        if milliseconds > 0 {
            return String(format: "%02llu:%02llu.%03llu", minutes, seconds, milliseconds)
        }
        return String(format: "%02llu:%02llu", minutes, seconds)
    }

    private static func formatSpeed(_ speed: Float) -> String {
        if speed.rounded(.towardZero) == speed {
            return "\(Int(speed))"
        }
        return String(format: "%.1f", speed)
    }

    private static func formatBytes(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}
