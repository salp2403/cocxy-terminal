// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteSearchGrep.swift - Default search backend: case-insensitive
// substring match performed in memory.

import Foundation

/// Default search backend.
///
/// Loads every note in the workspace via the supplied `NoteStore`,
/// filters by case-insensitive substring match, and ranks hits by the
/// number of occurrences (more matches → higher score). Suitable for
/// up to a few hundred notes per workspace; users with thousands of
/// notes should switch to `.fts5`.
///
/// Pure value type so the factory can hand out fresh instances per
/// search without lifecycle bookkeeping.
struct NoteSearchGrep: NoteSearching {

    let kind: NoteSearchEngineKind = .grep

    /// Store the engine reads from. Held as a strong reference because
    /// the actor's lifecycle is owned by the application (the
    /// `MainWindowController`) — leaking the store would mean leaking
    /// the entire feature, which is a much louder signal.
    let store: NoteStore

    /// Maximum characters of context shown around the matched term in
    /// the preview. Small enough to keep the list row compact, large
    /// enough to give the user usable context.
    let previewWindow: Int

    init(store: NoteStore, previewWindow: Int = 80) {
        self.store = store
        self.previewWindow = previewWindow
    }

    func search(
        query: String,
        in workspaceID: NoteWorkspaceID
    ) async throws -> [NoteSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let notes = try await store.notes(in: workspaceID)
        let needle = trimmed.lowercased()

        var hits: [NoteSearchResult] = []
        for note in notes {
            let lowerBody = note.body.lowercased()
            let occurrences = Self.countOccurrences(of: needle, in: lowerBody)
            guard occurrences > 0 else { continue }
            let title = Note.deriveTitle(from: note.body)
            let preview = Self.makePreview(
                body: note.body,
                needle: trimmed,
                window: previewWindow
            )
            let score = Self.normaliseScore(occurrences: occurrences)
            hits.append(
                NoteSearchResult(
                    noteID: note.id,
                    title: title,
                    preview: preview,
                    score: score
                )
            )
        }
        return hits.sorted { $0.score > $1.score }
    }

    // MARK: - Pure helpers (exposed for tests)

    /// Counts non-overlapping occurrences of `needle` (already
    /// lowercased) inside `haystack` (already lowercased). Handles the
    /// empty-needle case explicitly so the caller never gets a divide
    /// by zero.
    static func countOccurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }

    /// Builds a short excerpt around the first match. When the body is
    /// shorter than the window or the match is at the start, the
    /// excerpt is anchored to the beginning of the body. Adds an
    /// ellipsis at either end when truncation occurred so the user can
    /// see they are looking at a snippet.
    static func makePreview(body: String, needle: String, window: Int) -> String {
        guard let range = body.range(of: needle, options: .caseInsensitive) else {
            return String(body.prefix(window))
        }
        let half = max(0, window / 2)
        let start = body.index(range.lowerBound, offsetBy: -half, limitedBy: body.startIndex)
            ?? body.startIndex
        let end = body.index(range.upperBound, offsetBy: half, limitedBy: body.endIndex)
            ?? body.endIndex
        let prefix = start > body.startIndex ? "…" : ""
        let suffix = end < body.endIndex ? "…" : ""
        let snippet = String(body[start..<end])
            .replacingOccurrences(of: "\n", with: " ")
        return prefix + snippet + suffix
    }

    /// Maps the raw occurrence count onto `[0, 1]` using a smooth
    /// asymptote. Picked to keep a 1-occurrence hit visible on the
    /// score bar while still giving room for very strong hits to
    /// approach 1.0.
    static func normaliseScore(occurrences: Int) -> Double {
        guard occurrences > 0 else { return 0 }
        let raw = Double(occurrences)
        return raw / (raw + 4.0)
    }
}
