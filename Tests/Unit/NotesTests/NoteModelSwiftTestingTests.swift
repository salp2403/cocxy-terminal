// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `Note` value-type contract: identity round-trips, derived
/// title prefers the heading line, excerpt skips the title line so the
/// list never duplicates content, Codable preserves every field. Pure
/// helpers are static so the test suite can exercise them without
/// instantiating the value type.
@Suite("Note")
struct NoteModelSwiftTestingTests {

    private static let workspaceID = NoteWorkspaceID(
        workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo")
    )

    // MARK: - Initializer defaults

    @Test("default initializer leaves the body empty so a freshly created note can stream through the editor")
    func defaultInitializerProducesEmptyBody() {
        let note = Note(workspaceID: Self.workspaceID)

        #expect(note.body.isEmpty)
        #expect(note.workspaceID == Self.workspaceID)
    }

    @Test("default initializer sets updatedAt to createdAt so a brand-new note never appears stale in the list")
    func defaultInitializerAlignsTimestamps() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let note = Note(workspaceID: Self.workspaceID, createdAt: now)

        #expect(note.createdAt == now)
        #expect(note.updatedAt == now)
    }

    @Test("explicit updatedAt overrides the default so the store can fix a saved-at timestamp without losing createdAt")
    func explicitUpdatedAtOverridesDefault() {
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_750_001_000)

        let note = Note(
            workspaceID: Self.workspaceID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        #expect(note.createdAt == createdAt)
        #expect(note.updatedAt == updatedAt)
    }

    // MARK: - deriveTitle

    @Test("deriveTitle strips a leading ATX heading so `# Hello` becomes `Hello` in the list")
    func deriveTitleStripsHeading() {
        #expect(Note.deriveTitle(from: "# Hello") == "Hello")
        #expect(Note.deriveTitle(from: "## Sub heading\nbody") == "Sub heading")
    }

    @Test("deriveTitle uses the first non-blank line when there is no heading so plain notes still get a title")
    func deriveTitleFallsBackToFirstLine() {
        #expect(Note.deriveTitle(from: "First line\nSecond line") == "First line")
    }

    @Test("deriveTitle skips leading blank lines so a stray newline does not produce an empty title")
    func deriveTitleSkipsLeadingBlanks() {
        #expect(Note.deriveTitle(from: "\n\n   \nReal content") == "Real content")
    }

    @Test("deriveTitle returns Untitled for an empty body so the list always has a label")
    func deriveTitleHandlesEmptyBody() {
        #expect(Note.deriveTitle(from: "") == "Untitled")
        #expect(Note.deriveTitle(from: "   \n   \n") == "Untitled")
    }

    @Test("localized title translates only the empty-note fallback and preserves authored titles")
    func localizedTitleTranslatesOnlyEmptyNoteFallback() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let empty = Note(workspaceID: Self.workspaceID)
        let titled = Note(workspaceID: Self.workspaceID, body: "# Roadmap\nNext step")

        #expect(empty.localizedDerivedTitle(using: spanish) == "Sin título")
        #expect(titled.localizedDerivedTitle(using: spanish) == "Roadmap")
        #expect(Note.localizedTitle("Untitled", using: spanish) == "Sin título")
        #expect(Note.localizedTitle("Custom", using: spanish) == "Custom")
    }

    @Test("deriveTitle ignores a heading line that has no content after the hashes so `# ` does not produce an empty title")
    func deriveTitleIgnoresEmptyHeading() {
        #expect(Note.deriveTitle(from: "#\nNot empty") == "Not empty")
        #expect(Note.deriveTitle(from: "###    \nReal") == "Real")
    }

    @Test("derivedTitle on the value type matches the static helper so consumers can use either entry point interchangeably")
    func instanceTitleMatchesStaticHelper() {
        let body = "# Heading line\nfirst paragraph"
        let note = Note(workspaceID: Self.workspaceID, body: body)

        #expect(note.derivedTitle == Note.deriveTitle(from: body))
    }

    // MARK: - deriveExcerpt

    @Test("excerpt skips the heading line so the list never shows the title twice")
    func excerptSkipsHeadingLine() {
        #expect(
            Note.deriveExcerpt(from: "# Title\nFirst paragraph", maxLength: 120)
                == "First paragraph"
        )
    }

    @Test("excerpt skips the first non-blank line when there is no heading so plain notes still preview the next line")
    func excerptSkipsFirstLineWithoutHeading() {
        #expect(
            Note.deriveExcerpt(from: "Title-y line\nNext content", maxLength: 120)
                == "Next content"
        )
    }

    @Test("excerpt truncates with an ellipsis so long previews do not blow up the row layout")
    func excerptTruncatesLongPreviews() {
        let title = "# Title"
        let longLine = String(repeating: "x", count: 200)
        let body = "\(title)\n\(longLine)"

        let preview = Note.deriveExcerpt(from: body, maxLength: 50)

        #expect(preview.hasSuffix("…"))
        #expect(preview.count == 51) // 50 chars + the ellipsis
    }

    @Test("excerpt returns an empty string when there is no second line so the list collapses gracefully on title-only notes")
    func excerptHandlesTitleOnlyNotes() {
        #expect(Note.deriveExcerpt(from: "# Just a title") == "")
        #expect(Note.deriveExcerpt(from: "") == "")
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves every field so persisted notes never lose data")
    func codableRoundTripPreservesEveryField() throws {
        let original = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            workspaceID: Self.workspaceID,
            body: "# Title\nbody content",
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_001_000)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Note.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("Equatable compares every persisted field so the store layer can detect real changes without false positives")
    func equatableComparesEveryField() {
        let base = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            workspaceID: Self.workspaceID,
            body: "body",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        var withDifferentBody = base
        withDifferentBody.body = "different"
        #expect(withDifferentBody != base)

        var withDifferentUpdatedAt = base
        withDifferentUpdatedAt.updatedAt = Date(timeIntervalSince1970: 2_000)
        #expect(withDifferentUpdatedAt != base)
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
