// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteSearching.swift - Protocol and value types for the configurable
// note search engine.

import Foundation

/// Closed enum of search backends the user can pick via
/// `[notes].search-engine` in the TOML config.
///
/// Four implementations ship out of the box:
///
///   * `.grep` — case-insensitive substring match in memory. Default
///     because it has zero dependencies, no index to maintain, and is
///     instant for hundreds of notes.
///   * `.ripgrep` — bundled file search through the local `rg` helper.
///     Falls back to `.grep` if the helper is unavailable.
///   * `.fts5` — SQLite FTS5 index persisted under
///     `~/.config/cocxy/notes/.search/`. Scales to thousands of notes
///     and supports proper ranking; requires the `sqlite3` CLI on the
///     user's `PATH`.
///   * `.spotlight` — `NSMetadataQuery` against the macOS Spotlight
///     index. Zero local index, but only finds notes Spotlight has
///     already indexed.
///
/// Pinned as a closed enum so the factory and the config parser match
/// exhaustively and the compiler flags any future addition.
enum NoteSearchEngineKind: String, Sendable, Codable, Equatable, CaseIterable {

    case grep
    case ripgrep
    case fts5
    case spotlight

    /// Used when the TOML config key is missing or malformed.
    static let `default`: NoteSearchEngineKind = .grep

    /// Tolerant parser for the TOML key. Returns `.default` on any
    /// unknown value so user typos never block the load path.
    static func parse(_ raw: String?) -> NoteSearchEngineKind {
        guard let raw else { return .default }
        return NoteSearchEngineKind(rawValue: raw) ?? .default
    }
}

/// One hit returned by a search backend.
///
/// `score` is normalised to `[0, 1]` so the UI can render relative
/// confidence with a consistent color ramp regardless of which engine
/// produced the hit. The `preview` field is a short excerpt around the
/// match suitable for inline rendering — the engine guarantees it
/// contains at least one occurrence of the search term when a non-zero
/// score is reported.
struct NoteSearchResult: Sendable, Equatable, Identifiable {

    let noteID: UUID
    let title: String
    let preview: String
    let score: Double

    var id: UUID { noteID }
}

/// Common contract for every search backend. `Sendable` so callers can
/// dispatch searches off the main actor.
///
/// Implementations are free to surface backend-specific errors via
/// `throws`; the UI catches and shows a banner. Returning an empty
/// array is the canonical "no hits" signal — never `nil`.
protocol NoteSearching: Sendable {

    /// Identifier of the kind of engine. Tests use it to assert that
    /// the factory returned the expected implementation; the UI can
    /// surface it in the search bar's diagnostics.
    var kind: NoteSearchEngineKind { get }

    /// Searches notes in `workspaceID` for `query`. Whitespace-only
    /// queries return an empty array so the UI never has to special
    /// case the empty input itself.
    func search(
        query: String,
        in workspaceID: NoteWorkspaceID
    ) async throws -> [NoteSearchResult]
}
