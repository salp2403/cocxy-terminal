// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `NoteSearchGrep` contract: case-insensitive substring
/// match, occurrence-count ranking, preview clamped to the configured
/// window. Pure helpers tested separately so future implementations
/// can reuse them without re-implementing the suite.
@Suite("NoteSearchGrep", .serialized)
struct NoteSearchGrepSwiftTestingTests {

    private static let workspaceID = NoteWorkspaceID(
        workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo")
    )

    private func makeStore() -> (NoteStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "cocxy-search-grep-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        return (NoteStore(storageRoot: root, format: .markdown), root)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Pure helpers

    @Test("countOccurrences returns zero for an empty needle so the score normalisation never divides by zero")
    func countOccurrencesHandlesEmptyNeedle() {
        #expect(NoteSearchGrep.countOccurrences(of: "", in: "anything") == 0)
    }

    @Test("countOccurrences counts non-overlapping hits so a multi-match note ranks higher than a single match")
    func countOccurrencesCountsMultipleMatches() {
        #expect(NoteSearchGrep.countOccurrences(of: "test", in: "test test test") == 3)
        #expect(NoteSearchGrep.countOccurrences(of: "test", in: "no match here") == 0)
        #expect(NoteSearchGrep.countOccurrences(of: "ab", in: "abab") == 2)
    }

    @Test("normaliseScore is monotonic and bounded so the UI's score ramp behaves predictably")
    func normaliseScoreIsMonotonicBounded() {
        let one = NoteSearchGrep.normaliseScore(occurrences: 1)
        let many = NoteSearchGrep.normaliseScore(occurrences: 100)
        let zero = NoteSearchGrep.normaliseScore(occurrences: 0)

        #expect(zero == 0)
        #expect(one > 0 && one < 1)
        #expect(many > one)
        #expect(many < 1)
    }

    @Test("makePreview anchors around the first match so the user sees the matched substring in context")
    func previewAnchorsAroundFirstMatch() {
        let body = String(repeating: "x", count: 200)
            + "needle"
            + String(repeating: "y", count: 200)

        let preview = NoteSearchGrep.makePreview(body: body, needle: "needle", window: 80)

        #expect(preview.contains("needle"))
        #expect(preview.hasPrefix("…"))
        #expect(preview.hasSuffix("…"))
    }

    @Test("makePreview falls back to the body prefix when the needle is missing so the UI still shows context")
    func previewFallsBackWhenNeedleMissing() {
        let body = "no match anywhere"

        let preview = NoteSearchGrep.makePreview(body: body, needle: "xyz", window: 80)

        #expect(preview == body)
    }

    @Test("makePreview replaces newlines with spaces so the row stays single-line in the list")
    func previewReplacesNewlines() {
        let body = "line one\nline two needle\nline three"

        let preview = NoteSearchGrep.makePreview(body: body, needle: "needle", window: 80)

        #expect(preview.contains("\n") == false)
        #expect(preview.contains("needle"))
    }

    // MARK: - End-to-end search

    @Test("search returns an empty array for whitespace-only queries so the UI does not have to special case the empty input")
    func searchReturnsEmptyForBlankQuery() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }
        _ = try await store.create(in: Self.workspaceID, body: "any body")
        let engine = NoteSearchGrep(store: store)

        #expect(try await engine.search(query: "", in: Self.workspaceID).isEmpty)
        #expect(try await engine.search(query: "   ", in: Self.workspaceID).isEmpty)
    }

    @Test("search matches case-insensitively so users do not have to remember capitalisation")
    func searchMatchesCaseInsensitively() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }
        let saved = try await store.create(in: Self.workspaceID, body: "# Title\nThe quick BROWN fox")
        let engine = NoteSearchGrep(store: store)

        let hits = try await engine.search(query: "brown", in: Self.workspaceID)

        #expect(hits.count == 1)
        #expect(hits.first?.noteID == saved.id)
        #expect(hits.first?.title == "Title")
    }

    @Test("search ranks more occurrences higher so the most relevant note bubbles to the top")
    func searchRanksByOccurrences() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }
        let single = try await store.create(in: Self.workspaceID, body: "needle in haystack")
        let triple = try await store.create(in: Self.workspaceID, body: "needle needle needle")
        let engine = NoteSearchGrep(store: store)

        let hits = try await engine.search(query: "needle", in: Self.workspaceID)

        #expect(hits.count == 2)
        #expect(hits.first?.noteID == triple.id)
        #expect(hits.last?.noteID == single.id)
    }

    @Test("search excludes notes that do not contain the query so the result list is precise")
    func searchExcludesNonMatchingNotes() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }
        _ = try await store.create(in: Self.workspaceID, body: "no relevant content")
        _ = try await store.create(in: Self.workspaceID, body: "matched body")
        let engine = NoteSearchGrep(store: store)

        let hits = try await engine.search(query: "matched", in: Self.workspaceID)

        #expect(hits.count == 1)
    }

    @Test("kind is grep so the factory and the diagnostics layer can recognise the engine")
    func kindIsGrep() {
        let (store, root) = makeStore()
        defer { cleanup(root) }
        let engine = NoteSearchGrep(store: store)
        #expect(engine.kind == .grep)
    }
}
