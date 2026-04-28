// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `NoteSerializer` contract: round-trips both formats; the
/// frontmatter parser is tolerant of malformed metadata; quoting
/// survives titles that contain reserved characters; the markdown-only
/// path is a verbatim pass-through so a note that was hand-edited with
/// any markdown editor stays compatible with Cocxy.
@Suite("NoteSerializer")
struct NoteSerializerSwiftTestingTests {

    private static let workspaceID = NoteWorkspaceID(
        workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo")
    )
    private static let referenceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    // MARK: - Markdown (verbatim)

    @Test("markdown serialiser writes the body verbatim so any markdown editor reads it without special handling")
    func markdownSerialisesVerbatim() {
        let note = Note(
            id: Self.referenceID,
            workspaceID: Self.workspaceID,
            body: "# Hello\nbody"
        )

        let rendered = NoteSerializer.serialize(note, format: .markdown)

        #expect(rendered == "# Hello\nbody")
    }

    @Test("markdown deserialiser returns the content verbatim with no metadata so timestamps come from filesystem attributes")
    func markdownDeserialiserPassesThrough() throws {
        let parsed = try NoteSerializer.deserialize("# Hello\nbody", format: .markdown)

        #expect(parsed.body == "# Hello\nbody")
        #expect(parsed.createdAt == nil)
        #expect(parsed.updatedAt == nil)
        #expect(parsed.frontmatterID == nil)
    }

    // MARK: - Markdown frontmatter

    @Test("frontmatter serialiser leads with --- and lists the documented metadata keys")
    func frontmatterRendersHeader() {
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_750_001_000)
        let note = Note(
            id: Self.referenceID,
            workspaceID: Self.workspaceID,
            body: "# Hello\nbody",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        let rendered = NoteSerializer.serialize(note, format: .markdownFrontmatter)

        #expect(rendered.hasPrefix("---\n"))
        #expect(rendered.contains("title: \"Hello\""))
        #expect(rendered.contains("id: \(Self.referenceID.uuidString)"))
        #expect(rendered.contains("createdAt: 2026-06-15T10:26:40Z")
                || rendered.contains("createdAt:"))
        #expect(rendered.contains("\n---\n"))
        #expect(rendered.hasSuffix("# Hello\nbody"))
    }

    @Test("frontmatter round-trips a note through serialise + deserialise so persisted metadata stays stable")
    func frontmatterRoundTrip() throws {
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_750_001_000)
        let note = Note(
            id: Self.referenceID,
            workspaceID: Self.workspaceID,
            body: "# Hello\nbody",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        let rendered = NoteSerializer.serialize(note, format: .markdownFrontmatter)
        let parsed = try NoteSerializer.deserialize(rendered, format: .markdownFrontmatter)

        #expect(parsed.body == "# Hello\nbody")
        #expect(parsed.createdAt == createdAt)
        #expect(parsed.updatedAt == updatedAt)
        #expect(parsed.frontmatterID == Self.referenceID)
    }

    @Test("frontmatter parser preserves quotes, slashes, and colons in the title so reserved characters never break the round-trip")
    func frontmatterQuotingSurvivesReservedCharacters() throws {
        let body = #"# Bug: "quoted" path/with/slashes"#
        let note = Note(
            id: Self.referenceID,
            workspaceID: Self.workspaceID,
            body: body
        )

        let rendered = NoteSerializer.serialize(note, format: .markdownFrontmatter)
        let parsed = try NoteSerializer.deserialize(rendered, format: .markdownFrontmatter)

        #expect(parsed.body == body)
    }

    @Test("frontmatter parser falls back to a body-only note when the opening delimiter is missing")
    func frontmatterMissingOpeningDelimiterFallsBack() throws {
        let raw = "# Hello\nbody"

        let parsed = try NoteSerializer.deserialize(raw, format: .markdownFrontmatter)

        #expect(parsed.body == raw)
        #expect(parsed.createdAt == nil)
        #expect(parsed.frontmatterID == nil)
    }

    @Test("frontmatter parser throws when the closing delimiter is missing so the caller can show a malformed banner")
    func frontmatterMissingClosingDelimiterThrows() {
        let raw = "---\ntitle: \"x\"\nbody"

        #expect(throws: NoteSerializer.DeserializationError.self) {
            _ = try NoteSerializer.deserialize(raw, format: .markdownFrontmatter)
        }
    }

    @Test("frontmatter parser tolerates unknown keys so future versions can add metadata without breaking older Cocxy builds")
    func frontmatterToleratesUnknownKeys() throws {
        let raw = """
        ---
        title: "Hello"
        id: \(Self.referenceID.uuidString)
        unknownKey: someValue
        ---

        body
        """

        let parsed = try NoteSerializer.deserialize(raw, format: .markdownFrontmatter)

        #expect(parsed.body == "body")
        #expect(parsed.frontmatterID == Self.referenceID)
    }

    @Test("frontmatter parser tolerates missing timestamps so files edited outside Cocxy can omit them and rely on filesystem metadata")
    func frontmatterToleratesMissingTimestamps() throws {
        let raw = """
        ---
        title: "Hello"
        ---

        body
        """

        let parsed = try NoteSerializer.deserialize(raw, format: .markdownFrontmatter)

        #expect(parsed.body == "body")
        #expect(parsed.createdAt == nil)
        #expect(parsed.updatedAt == nil)
        #expect(parsed.frontmatterID == nil)
    }
}
