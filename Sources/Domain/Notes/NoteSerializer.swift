// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteSerializer.swift - Pure helpers that turn a `Note` into the
// on-disk representation and back, format-aware.

import Foundation

/// Pure serialiser / deserialiser for notes.
///
/// Decoupling the disk format from `Note` itself keeps the value type
/// minimal and lets the unit suite cover format-specific edge cases
/// (frontmatter parsing, missing keys, malformed dates) without
/// instantiating a `NoteStore` or touching the filesystem.
///
/// ## Formats
///
/// * `.markdown` — body verbatim. Loading reconstructs `createdAt` /
///   `updatedAt` from the file's filesystem attributes; the saver
///   relies on the OS to update the modification time.
/// * `.markdownFrontmatter` — adds a YAML frontmatter block delimited
///   by `---` lines that carries `title`, `createdAt`, `updatedAt`.
///   Loading parses the block tolerantly: malformed or missing keys
///   fall back to the equivalent file-system metadata.
enum NoteSerializer {

    // MARK: - Errors

    /// Errors surfaced when a stored file cannot be turned back into a
    /// `Note`. Distinct from generic I/O errors so the caller can
    /// distinguish "the file is not a Cocxy note" from "the file is
    /// missing".
    enum DeserializationError: Error, Sendable, Equatable {
        case malformedFrontmatter(String)
    }

    // MARK: - Serialisation

    /// Renders `note` into the supplied `format`. Pure function — the
    /// caller is responsible for writing the result to disk and for
    /// updating `note.updatedAt` before serialising if the underlying
    /// content changed.
    static func serialize(_ note: Note, format: NoteFormat) -> String {
        switch format {
        case .markdown:
            return note.body
        case .markdownFrontmatter:
            return renderFrontmatter(note: note) + note.body
        }
    }

    /// Builds the YAML frontmatter block for `note`. Kept `static` and
    /// `private` so the test suite cannot assert against an opaque
    /// internal helper — frontmatter behaviour is exercised through
    /// the round-trip tests of `serialize` / `deserialize`.
    private static func renderFrontmatter(note: Note) -> String {
        let title = Note.deriveTitle(from: note.body)
        // YAML strings that may contain colons or other reserved
        // characters are wrapped in double quotes and have any
        // embedded quotes / backslashes escaped, so a title like
        // `Bug: "quoted"` survives the round-trip.
        let safeTitle = escape(title)
        let createdAt = isoFormatter.string(from: note.createdAt)
        let updatedAt = isoFormatter.string(from: note.updatedAt)
        return """
        ---
        title: "\(safeTitle)"
        id: \(note.id.uuidString)
        createdAt: \(createdAt)
        updatedAt: \(updatedAt)
        ---

        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Deserialisation

    /// Result returned by `deserialize` so the caller can recover both
    /// the typed note and any header-only metadata (e.g. an `id`
    /// embedded in the frontmatter that the caller wants to honour
    /// instead of trusting the filename).
    struct DeserialisedNote: Sendable, Equatable {
        let body: String
        let createdAt: Date?
        let updatedAt: Date?
        let frontmatterID: UUID?
    }

    /// Parses `content` into a typed body / metadata pair given the
    /// `format` that produced it. Tolerant of malformed metadata —
    /// missing keys, bad dates, and extra unrecognised keys all
    /// degrade gracefully so a damaged file never blocks the rest of
    /// the workspace from loading.
    static func deserialize(
        _ content: String,
        format: NoteFormat
    ) throws -> DeserialisedNote {
        switch format {
        case .markdown:
            return DeserialisedNote(
                body: content,
                createdAt: nil,
                updatedAt: nil,
                frontmatterID: nil
            )
        case .markdownFrontmatter:
            return try parseFrontmatter(content)
        }
    }

    private static func parseFrontmatter(_ content: String) throws -> DeserialisedNote {
        // A frontmatter block must start at offset 0 with a `---` line
        // followed by zero or more `key: value` lines, terminated by
        // another `---` line. If the opening delimiter is missing, we
        // fall back to treating the whole content as a body.
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == "---"
        else {
            return DeserialisedNote(
                body: content,
                createdAt: nil,
                updatedAt: nil,
                frontmatterID: nil
            )
        }

        var headerEndIndex: Int?
        for index in 1..<lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == "---" {
                headerEndIndex = index
                break
            }
        }
        guard let headerEndIndex else {
            throw DeserializationError.malformedFrontmatter("missing closing delimiter")
        }

        var values: [String: String] = [:]
        for index in 1..<headerEndIndex {
            let line = String(lines[index])
            guard let separator = line.firstIndex(of: ":") else { continue }
            let rawKey = String(line[line.startIndex..<separator])
                .trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            values[rawKey] = unquote(rawValue)
        }

        let bodyStartIndex = headerEndIndex + 1
        let bodyLines: ArraySlice<Substring>
        if bodyStartIndex < lines.count {
            bodyLines = lines[bodyStartIndex...]
        } else {
            bodyLines = ArraySlice<Substring>([])
        }
        // Drop a single blank line right after the frontmatter so the
        // body content stays clean — the renderer always emits one.
        var trimmed = Array(bodyLines)
        if let firstBodyLine = trimmed.first,
           firstBodyLine.trimmingCharacters(in: .whitespaces).isEmpty {
            trimmed.removeFirst()
        }
        let body = trimmed.joined(separator: "\n")

        let createdAt = values["createdAt"].flatMap { isoFormatter.date(from: $0) }
        let updatedAt = values["updatedAt"].flatMap { isoFormatter.date(from: $0) }
        let frontmatterID = values["id"].flatMap { UUID(uuidString: $0) }

        return DeserialisedNote(
            body: body,
            createdAt: createdAt,
            updatedAt: updatedAt,
            frontmatterID: frontmatterID
        )
    }

    private static func unquote(_ raw: String) -> String {
        guard raw.count >= 2,
              raw.hasPrefix("\""),
              raw.hasSuffix("\"")
        else { return raw }
        let inner = String(raw.dropFirst().dropLast())
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - Date formatter

    /// Shared ISO-8601 formatter for the frontmatter timestamps. Uses
    /// the canonical `2026-04-27T12:34:56Z` shape so a frontmatter file
    /// edited outside Cocxy still round-trips through this parser.
    ///
    /// `nonisolated(unsafe)` because `ISO8601DateFormatter` inherits
    /// from `NSFormatter` (which is not `Sendable` at the type-system
    /// level), but Apple documents the formatter as safe to use
    /// concurrently from multiple threads once it has been configured.
    /// The configuration is set once at module init and never mutated.
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
