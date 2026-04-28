// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteSearchSpotlight.swift - Spotlight (`mdfind`) search backend.

import Foundation

/// Spotlight-backed search.
///
/// Calls `/usr/bin/mdfind -onlyin <workspace-folder> <query>` and maps
/// the returned file paths back onto `Note` values via `NoteStore`.
/// `mdfind` only returns matches for files Spotlight has indexed —
/// macOS hides dot-prefixed directories from the index by default, so
/// users on the default storage path (`~/.config/cocxy/notes/`) need
/// to opt their notes folder into the index. The recommended setup is:
///
/// ```bash
/// mdimport ~/.config/cocxy/notes
/// ```
///
/// or to add the folder to Spotlight via `System Settings > Siri &
/// Spotlight > Spotlight Privacy` and remove its parent from the
/// excluded list. The error case `spotlightFailed` surfaces a banner
/// in the UI when `mdfind` is unavailable.
///
/// Subprocess-based instead of `NSMetadataQuery` because:
///
///   * `NSMetadataQuery` runs an internal runloop, which conflicts
///     with the XCTest gate documented in
///     `feedback_xctest_timer_publish_runloop`.
///   * The CLI returns synchronous output that's trivially testable
///     by replacing `mdfindPath` with a fixture executable.
///   * Cocxy already shells out to `sqlite3` for the FTS5 backend, so
///     reusing the Process plumbing keeps the code base smaller.
struct NoteSearchSpotlight: NoteSearching {

    let kind: NoteSearchEngineKind = .spotlight

    /// Store used to map result paths back onto `Note` values.
    let store: NoteStore

    /// Storage root the workspace folders live under. The backend
    /// scopes `mdfind -onlyin` to the workspace folder under this root
    /// so cross-workspace matches never leak.
    let storageRoot: URL

    /// Path to `mdfind`. Defaults to the macOS native binary; tests
    /// override it with a stub script that returns canned output.
    let mdfindPath: URL

    init(
        store: NoteStore,
        storageRoot: URL,
        mdfindPath: URL = URL(fileURLWithPath: "/usr/bin/mdfind")
    ) {
        self.store = store
        self.storageRoot = storageRoot
        self.mdfindPath = mdfindPath
    }

    func search(
        query: String,
        in workspaceID: NoteWorkspaceID
    ) async throws -> [NoteSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let workspaceDir = storageRoot
            .appendingPathComponent(workspaceID.rawValue, isDirectory: true)
        guard FileManager.default.fileExists(atPath: workspaceDir.path) else {
            return []
        }

        guard FileManager.default.isExecutableFile(atPath: mdfindPath.path) else {
            throw NoteSearchError.spotlightFailed(
                message: "mdfind not available at \(mdfindPath.path)"
            )
        }

        let paths = try runMdfind(query: trimmed, scope: workspaceDir)
        let noteIDs = Self.parseNoteIDs(from: paths)
        guard !noteIDs.isEmpty else { return [] }

        let notes = try await store.notes(in: workspaceID)
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })

        return Self.composeResults(
            noteIDs: noteIDs,
            notesByID: byID,
            needle: trimmed
        )
    }

    // MARK: - Pure helpers (exposed for tests)

    /// Maps absolute paths returned by `mdfind` back onto note UUIDs.
    /// Drops anything whose stem is not a valid UUID (Spotlight may
    /// return unrelated files inside the workspace folder, e.g. an
    /// FTS5 index leftover from a previous engine selection).
    static func parseNoteIDs(from paths: [String]) -> [UUID] {
        paths.compactMap { rawPath in
            let url = URL(fileURLWithPath: rawPath)
            let stem = url.deletingPathExtension().lastPathComponent
            return UUID(uuidString: stem)
        }
    }

    /// Builds the typed result array. Spotlight does not report a
    /// per-hit score, so every result lands at the same nominal value
    /// — the UI groups them together as "Spotlight matches" without a
    /// finer ranking. Callers that need ranking should pick `.fts5`.
    static func composeResults(
        noteIDs: [UUID],
        notesByID: [UUID: Note],
        needle: String
    ) -> [NoteSearchResult] {
        var results: [NoteSearchResult] = []
        for id in noteIDs {
            guard let note = notesByID[id] else { continue }
            let title = Note.deriveTitle(from: note.body)
            let preview = NoteSearchGrep.makePreview(
                body: note.body,
                needle: needle,
                window: 80
            )
            results.append(
                NoteSearchResult(
                    noteID: id,
                    title: title,
                    preview: preview,
                    score: 1.0
                )
            )
        }
        return results
    }

    // MARK: - Process plumbing

    private func runMdfind(query: String, scope: URL) throws -> [String] {
        let process = Process()
        process.executableURL = mdfindPath
        process.arguments = [
            "-onlyin", scope.path,
            query
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let group = DispatchGroup()
        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let queue = DispatchQueue.global(qos: .userInitiated)

        group.enter()
        queue.async {
            stdoutBox.store(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        queue.async {
            stderrBox.store(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        do {
            try process.run()
        } catch {
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            group.wait()
            throw NoteSearchError.spotlightFailed(message: error.localizedDescription)
        }

        process.waitUntilExit()
        group.wait()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: stderrBox.value, encoding: .utf8) ?? "unknown mdfind error"
            throw NoteSearchError.spotlightFailed(message: errorMessage)
        }

        let stdout = String(data: stdoutBox.value, encoding: .utf8) ?? ""
        return stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}

/// Local `Sendable` box mirroring the helper used by `NoteSearchFTS5`.
/// Kept private to this file so the search-engines layer does not leak
/// a shared utility outside the module — both files use a value-type
/// process result and the duplication is ~5 lines.
private final class DataBox: @unchecked Sendable {
    private var data = Data()
    func store(_ payload: Data) { data = payload }
    var value: Data { data }
}
