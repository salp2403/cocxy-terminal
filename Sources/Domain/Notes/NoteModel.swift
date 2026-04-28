// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteModel.swift - Value type representing a single note in the
// Notes module.

import Foundation

/// One note in the Notes module.
///
/// `Note` is a pure value type — `Sendable`, `Equatable`, `Codable`,
/// `Identifiable` — so it crosses actor boundaries cleanly, plays well
/// with SwiftUI list diffing, and round-trips through the persistence
/// layer without bespoke serialisation.
///
/// ## Title derivation
///
/// The user does not type a title separately from the body. The
/// effective title is derived from the body content:
///
///   * If the body starts with a `# ` line, the rest of that line is
///     the title.
///   * Otherwise the first non-blank line is used.
///   * If the body is empty or contains only whitespace, the title is
///     `"Untitled"`.
///
/// Storing only the body keeps the file format minimal: notes serialise
/// as plain markdown (or markdown + YAML frontmatter when the user
/// picks `.markdownFrontmatter`). The frontmatter variant adds an
/// explicit `title` field so a note can keep a custom title even when
/// the body is empty — the renderer prefers the frontmatter title when
/// present.
///
/// ## Identity
///
/// `id` is a fresh `UUID` per note, used as the on-disk filename
/// (`<id>.md` inside the workspace folder). The store layer maps file
/// names back to IDs so deleting / renaming the file is the same
/// operation as deleting / renaming the note.
struct Note: Sendable, Equatable, Codable, Identifiable {

    /// Unique identifier — used as the on-disk filename and as the
    /// SwiftUI list identity. Stable across saves; never re-used after
    /// the note is deleted.
    let id: UUID

    /// Workspace this note belongs to. Notes never move between
    /// workspaces; if the user drags one across, the store creates a
    /// new note with a fresh ID in the destination workspace.
    let workspaceID: NoteWorkspaceID

    /// Markdown body. May start with a `# Heading` line to give the
    /// note a derived title; otherwise the first non-blank line is
    /// used.
    var body: String

    /// Wall-clock timestamp at which the note was first persisted.
    /// Read-only after creation so the sort-by-creation list stays
    /// stable across edits.
    let createdAt: Date

    /// Wall-clock timestamp of the last save. Bumped by the store
    /// whenever the body changes; lets the list view sort by
    /// recently-edited and the tooltip surface "edited 5 min ago".
    var updatedAt: Date

    /// Convenience initializer that fills `id`, timestamps, and an
    /// empty body. Call sites that need explicit values continue to
    /// use the synthesised member-wise initializer; this overload
    /// exists so the common "create empty note in workspace" path is
    /// one line.
    init(
        id: UUID = UUID(),
        workspaceID: NoteWorkspaceID,
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    // MARK: - Derived metadata

    /// Title derived from the body. See type-level documentation for
    /// the full priority list (frontmatter title not yet considered —
    /// resolver layer composes that on top of this raw derivation).
    var derivedTitle: String {
        Self.deriveTitle(from: body)
    }

    /// Pure helper exposed for the store, the search engines, and the
    /// tests so they can derive a title without instantiating a `Note`.
    /// Kept `static` so it does not allocate, and so its contract is
    /// stable across refactors of the value type itself.
    static func deriveTitle(from body: String) -> String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") {
                // ATX heading — strip the leading hashes and any extra
                // whitespace so `# Hello` becomes `Hello`.
                let stripped = trimmed.drop { $0 == "#" }
                let title = stripped.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    return title
                }
                // Empty heading (e.g. `#` on its own or `###   `):
                // treat the line as decoration and keep walking so the
                // next non-blank line provides the title instead of
                // returning the bare hash characters.
                continue
            }
            return trimmed
        }
        return "Untitled"
    }

    // MARK: - Excerpt

    /// Short preview of the body shown next to the title in the list.
    /// Skips the heading line (when present) so the preview is the
    /// next line of content rather than a duplicate of the title.
    /// Cropped to `maxLength` characters; trailing whitespace trimmed.
    func excerpt(maxLength: Int = 120) -> String {
        Self.deriveExcerpt(from: body, maxLength: maxLength)
    }

    /// Pure helper for the excerpt rendering. Kept `static` for the
    /// same reasons as `deriveTitle(from:)`.
    static func deriveExcerpt(from body: String, maxLength: Int = 120) -> String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        var titleConsumed = false
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Skip the title line so the excerpt is fresh content.
            if !titleConsumed {
                titleConsumed = true
                continue
            }
            if trimmed.count <= maxLength { return trimmed }
            return String(trimmed.prefix(maxLength)) + "…"
        }
        return ""
    }
}
