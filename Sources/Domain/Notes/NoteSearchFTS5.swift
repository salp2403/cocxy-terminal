// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteSearchFTS5.swift - SQLite FTS5-backed search backend.

import Foundation

/// Errors surfaced by the SQLite-backed and Spotlight-backed search
/// engines. Distinct cases let the UI surface a useful banner instead
/// of a generic "search failed".
enum NoteSearchError: Error, Sendable, Equatable {

    /// `sqlite3` could not be located on the user's `PATH`. The UI
    /// renders a banner suggesting the user install the CLI or pick a
    /// different engine.
    case sqlite3NotFound(path: String)

    /// `sqlite3` was found but exited non-zero. Carries the captured
    /// stderr so the banner can surface the actual sqlite error
    /// (typo in the query, FTS5 not compiled in, etc.).
    case sqlite3Failed(message: String)

    /// `NSMetadataQuery` reported an error or timed out. Carries the
    /// localised description for the banner.
    case spotlightFailed(message: String)
}

/// SQLite FTS5 search backend.
///
/// Stateless: every search builds a fresh in-memory FTS5 index from
/// the workspace's notes, runs the query, and discards the index.
/// Pros: no index file to keep in sync with the on-disk notes; works
/// even when the user edits notes outside Cocxy. Cons: O(N) per search
/// to rebuild the index — acceptable for hundreds of notes, not for
/// tens of thousands.
///
/// Persisting the index across invocations is a future optimisation
/// gated on actual user demand. The protocol surface is stable, so
/// upgrading the implementation later is purely internal.
struct NoteSearchFTS5: NoteSearching {

    let kind: NoteSearchEngineKind = .fts5

    /// Store this backend reads from when assembling the in-memory
    /// index. Held strong for the same reason as `NoteSearchGrep`.
    let store: NoteStore

    /// Path to the `sqlite3` binary. Defaults to the macOS native
    /// `/usr/bin/sqlite3` (FTS5-enabled in 3.43+); tests can override
    /// to point at a stub binary.
    let sqlite3Path: URL

    /// Maximum number of hits returned. Mirrors `NoteSearchGrep`'s
    /// implicit cap so the two backends produce comparable result
    /// sizes regardless of which one the user picks.
    let resultLimit: Int

    init(
        store: NoteStore,
        sqlite3Path: URL = URL(fileURLWithPath: "/usr/bin/sqlite3"),
        resultLimit: Int = 50
    ) {
        self.store = store
        self.sqlite3Path = sqlite3Path
        self.resultLimit = resultLimit
    }

    func search(
        query: String,
        in workspaceID: NoteWorkspaceID
    ) async throws -> [NoteSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let notes = try await store.notes(in: workspaceID)
        guard !notes.isEmpty else { return [] }

        guard FileManager.default.isExecutableFile(atPath: sqlite3Path.path) else {
            throw NoteSearchError.sqlite3NotFound(path: sqlite3Path.path)
        }

        let script = Self.buildScript(notes: notes, query: trimmed, limit: resultLimit)
        let output = try runSQLite(script: script)
        return Self.parseResults(output: output, notes: notes)
    }

    // MARK: - Pure helpers (exposed for tests)

    /// Builds the full sqlite script: FTS5 virtual table creation,
    /// row insertions for every note, and the MATCH query. Single
    /// quotes inside the body are doubled so the script stays
    /// well-formed regardless of note content.
    static func buildScript(notes: [Note], query: String, limit: Int) -> String {
        var lines: [String] = []
        // The trigram tokenizer matches partial words and is friendlier
        // to the user's typo expectations than the default unicode61
        // tokenizer for short queries.
        lines.append("CREATE VIRTUAL TABLE notes_fts USING fts5(note_id UNINDEXED, body, tokenize = 'trigram');")
        for note in notes {
            let escapedBody = note.body.replacingOccurrences(of: "'", with: "''")
            lines.append("INSERT INTO notes_fts(note_id, body) VALUES('\(note.id.uuidString)', '\(escapedBody)');")
        }
        let escapedQuery = sanitizeQuery(query)
        lines.append(
            "SELECT note_id || '|' || rank FROM notes_fts WHERE notes_fts MATCH '\(escapedQuery)' ORDER BY rank LIMIT \(limit);"
        )
        return lines.joined(separator: "\n") + "\n"
    }

    /// Wraps the user query in double quotes so FTS5 treats it as a
    /// phrase search, with embedded double quotes doubled per FTS5
    /// quoting rules. Embedded single quotes are doubled because the
    /// whole MATCH literal is itself wrapped in single quotes when
    /// embedded into the SQL script.
    static func sanitizeQuery(_ query: String) -> String {
        let doubleQuotesEscaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        let singleQuotesEscaped = doubleQuotesEscaped
            .replacingOccurrences(of: "'", with: "''")
        return "\"\(singleQuotesEscaped)\""
    }

    /// Parses the pipe-delimited `note_id|rank` output of the SELECT
    /// into typed `NoteSearchResult` values. FTS5 ranks are negative
    /// floats where a lower (more negative) value indicates a better
    /// match; the helper maps them onto `[0, 1]` so the UI's score
    /// ramp stays consistent across backends.
    static func parseResults(
        output: String,
        notes: [Note]
    ) -> [NoteSearchResult] {
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var results: [NoteSearchResult] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2,
                  let id = UUID(uuidString: String(parts[0])),
                  let rank = Double(parts[1]),
                  let note = byID[id]
            else { continue }
            let title = Note.deriveTitle(from: note.body)
            let preview = NoteSearchGrep.makePreview(
                body: note.body,
                needle: bestMatchHint(in: note.body),
                window: 80
            )
            results.append(
                NoteSearchResult(
                    noteID: note.id,
                    title: title,
                    preview: preview,
                    score: normaliseRank(rank)
                )
            )
        }
        return results
    }

    /// Maps an FTS5 rank score onto `[0, 1]`. FTS5 ranks are negative
    /// (lower = better); the helper applies a smooth, bounded curve so
    /// the very best hits approach 1.0 while a single weak match still
    /// scores above 0.
    static func normaliseRank(_ rank: Double) -> Double {
        let magnitude = abs(rank)
        return magnitude / (magnitude + 1.0)
    }

    /// Chooses a substring of the note body to anchor the preview on.
    /// Keeps the implementation simple — the first non-blank line is
    /// almost always the title, so the second non-blank line is the
    /// next best anchor. Falls back to the body's prefix.
    private static func bestMatchHint(in body: String) -> String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count >= 2 {
            return String(lines[1])
        }
        return String(body.prefix(40))
    }

    // MARK: - Process plumbing

    private func runSQLite(script: String) throws -> String {
        let process = Process()
        process.executableURL = sqlite3Path
        process.arguments = [":memory:"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
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
            // Close pipes so the readers see EOF and the group can settle
            // even though the child never spawned. Mirrors the pattern
            // captured in `feedback_dispatch_group_pipe_cleanup`.
            try? stdinPipe.fileHandleForWriting.close()
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            group.wait()
            throw NoteSearchError.sqlite3Failed(message: error.localizedDescription)
        }

        try? stdinPipe.fileHandleForWriting.write(contentsOf: Data(script.utf8))
        try? stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()
        group.wait()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: stderrBox.value, encoding: .utf8) ?? "unknown sqlite error"
            throw NoteSearchError.sqlite3Failed(message: errorMessage)
        }
        return String(data: stdoutBox.value, encoding: .utf8) ?? ""
    }
}

/// Tiny helper that lets a `DispatchQueue` block hand off `Data` to the
/// caller without an `inout` capture. `final class` so the box can
/// cross `Sendable` boundaries when the caller pins the lifetime.
private final class DataBox: @unchecked Sendable {
    private var data = Data()
    func store(_ payload: Data) { data = payload }
    var value: Data { data }
}
