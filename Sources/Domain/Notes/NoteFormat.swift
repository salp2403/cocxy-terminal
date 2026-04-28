// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteFormat.swift - User-selectable on-disk format for stored notes.

import Foundation

/// Persisted format the Notes module uses when writing a note to disk.
///
/// Configurable via `[notes].format` in the user's TOML config so each
/// user can pick the trade-off that fits their workflow:
///
///   * `.markdown` writes the body verbatim. Lightweight, opens cleanly
///     in any markdown editor, no metadata overhead.
///   * `.markdownFrontmatter` prepends a YAML frontmatter block
///     containing the note's metadata (id, title, timestamps). Heavier
///     but lets the note be shared / versioned outside Cocxy without
///     losing identity, and exposes user-editable tags / titles in a
///     human-friendly text format.
///
/// Keeping the format inside a closed enum (rather than a free-form
/// string) means the parser, the renderer, and the search engines all
/// match on a single source of truth — a future format can be added by
/// extending this enum and the `NoteFormat`-aware sites flagged by the
/// compiler.
enum NoteFormat: String, Sendable, Equatable, Codable, CaseIterable {

    /// Plain markdown body, no header. Default because every existing
    /// note tooling and `CocxyMarkdownLib` consumer renders it without
    /// special handling.
    case markdown = "markdown"

    /// Markdown body preceded by a YAML frontmatter block delimited by
    /// `---` lines. Used to surface metadata (title, tags, timestamps)
    /// in a human-editable form so notes round-trip cleanly outside
    /// Cocxy.
    case markdownFrontmatter = "markdown-frontmatter"

    /// Default format when the user has not picked one explicitly. The
    /// rest of the module falls back to this when a TOML value is
    /// missing or malformed (tolerant decoding).
    static let `default`: NoteFormat = .markdown

    /// Tolerant parser for the TOML / config key. Returns
    /// `NoteFormat.default` for unknown strings instead of failing —
    /// keeps the load path resilient to typos and to forward-compat
    /// when newer Cocxy versions add formats this build does not know.
    static func parse(_ raw: String?) -> NoteFormat {
        guard let raw else { return .default }
        return NoteFormat(rawValue: raw) ?? .default
    }

    /// File extension used when writing notes in this format. Both
    /// formats serialise to `.md` because the frontmatter variant is
    /// still a valid markdown document with extra metadata at the top.
    /// Keeping a single extension means every user-visible tool
    /// (Finder, search, editors) treats notes uniformly.
    var fileExtension: String {
        "md"
    }
}
