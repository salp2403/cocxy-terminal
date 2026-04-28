// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `NoteSearchSpotlight` contract: pure helpers map paths back
/// to typed `Note` values; the engine throws `spotlightFailed` when
/// the binary is missing; the search drops cross-workspace paths and
/// non-UUID stems. The end-to-end search uses a stub `mdfind` script
/// so it never depends on the user's real Spotlight index (which by
/// default does not cover `~/.config/`).
@Suite("NoteSearchSpotlight", .serialized)
struct NoteSearchSpotlightSwiftTestingTests {

    private static let workspaceID = NoteWorkspaceID(
        workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo")
    )

    private func makeStore() -> (NoteStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "cocxy-search-spotlight-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        return (NoteStore(storageRoot: root, format: .markdown), root)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes a stub `mdfind` script at a temporary path that prints
    /// `outputPaths` (one per line) regardless of arguments. Returns
    /// the URL of the script and a cleanup closure the caller invokes
    /// in `defer`.
    private func makeStubMdfind(outputPaths: [String]) throws -> (URL, () -> Void) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "cocxy-search-stub-mdfind-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let scriptURL = directory.appendingPathComponent("mdfind", isDirectory: false)
        let payload = outputPaths.map { "echo \"\($0)\"" }.joined(separator: "\n")
        let script = """
        #!/usr/bin/env bash
        \(payload)
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return (scriptURL, { try? FileManager.default.removeItem(at: directory) })
    }

    // MARK: - Pure helpers

    @Test("parseNoteIDs converts file paths into UUIDs so the search can map results back to notes")
    func parseNoteIDsConvertsPaths() {
        let id1 = UUID()
        let id2 = UUID()
        let paths = [
            "/Users/sample/.config/cocxy/notes/abc/\(id1.uuidString).md",
            "/Users/sample/.config/cocxy/notes/abc/\(id2.uuidString).md"
        ]

        let parsed = NoteSearchSpotlight.parseNoteIDs(from: paths)

        #expect(Set(parsed) == Set([id1, id2]))
    }

    @Test("parseNoteIDs drops non-UUID stems so unrelated files in the workspace folder do not leak into results")
    func parseNoteIDsDropsNonUUIDStems() {
        let id = UUID()
        let paths = [
            "/Users/sample/.config/cocxy/notes/abc/\(id.uuidString).md",
            "/Users/sample/.config/cocxy/notes/abc/index.md",
            "/Users/sample/.config/cocxy/notes/abc/.DS_Store"
        ]

        let parsed = NoteSearchSpotlight.parseNoteIDs(from: paths)

        #expect(parsed == [id])
    }

    @Test("composeResults skips IDs missing from the store so the UI never shows orphaned hits")
    func composeResultsSkipsUnknownIDs() {
        let valid = Note(workspaceID: Self.workspaceID, body: "valid body")
        let stranger = UUID()
        let byID = [valid.id: valid]

        let results = NoteSearchSpotlight.composeResults(
            noteIDs: [stranger, valid.id],
            notesByID: byID,
            needle: "valid"
        )

        #expect(results.count == 1)
        #expect(results.first?.noteID == valid.id)
    }

    @Test("composeResults assigns a uniform score so the UI can group Spotlight matches without spurious ranking")
    func composeResultsAssignsUniformScore() {
        let first = Note(workspaceID: Self.workspaceID, body: "first")
        let second = Note(workspaceID: Self.workspaceID, body: "second")
        let byID = [first.id: first, second.id: second]

        let results = NoteSearchSpotlight.composeResults(
            noteIDs: [first.id, second.id],
            notesByID: byID,
            needle: "first"
        )

        #expect(Set(results.map(\.score)) == [1.0])
    }

    // MARK: - End-to-end (with stub mdfind)

    @Test("search returns hits parsed from mdfind output so an existing note is matched even when Spotlight cannot index ~/.config/")
    func searchReturnsHitsFromStub() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }
        let saved = try await store.create(in: Self.workspaceID, body: "# Title\nbody alpha")

        let workspaceFolder = root.appendingPathComponent(Self.workspaceID.rawValue)
        let savedPath = workspaceFolder
            .appendingPathComponent("\(saved.id.uuidString).md")
            .path
        let (stubURL, stubCleanup) = try makeStubMdfind(outputPaths: [savedPath])
        defer { stubCleanup() }

        let engine = NoteSearchSpotlight(
            store: store,
            storageRoot: root,
            mdfindPath: stubURL
        )

        let hits = try await engine.search(query: "alpha", in: Self.workspaceID)

        #expect(hits.count == 1)
        #expect(hits.first?.noteID == saved.id)
    }

    @Test("search throws spotlightFailed when mdfind is missing so the UI surfaces a banner with a helpful message")
    func searchThrowsWhenBinaryMissing() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }
        _ = try await store.create(in: Self.workspaceID, body: "anything")

        let engine = NoteSearchSpotlight(
            store: store,
            storageRoot: root,
            mdfindPath: URL(fileURLWithPath: "/nonexistent/mdfind")
        )

        await #expect(throws: NoteSearchError.self) {
            _ = try await engine.search(query: "anything", in: Self.workspaceID)
        }
    }

    @Test("search returns an empty array for blank queries before reaching mdfind so the stub is never invoked")
    func searchReturnsEmptyForBlankQuery() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }

        let engine = NoteSearchSpotlight(store: store, storageRoot: root)
        let hits = try await engine.search(query: "  ", in: Self.workspaceID)

        #expect(hits.isEmpty)
    }

    @Test("search returns an empty array when the workspace folder does not exist so a fresh workspace is a no-op")
    func searchReturnsEmptyForUnknownWorkspace() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }

        let engine = NoteSearchSpotlight(store: store, storageRoot: root)
        let hits = try await engine.search(query: "alpha", in: Self.workspaceID)

        #expect(hits.isEmpty)
    }

    @Test("kind is spotlight so the factory and the diagnostics layer can recognise the engine")
    func kindIsSpotlight() {
        let (store, root) = makeStore()
        defer { cleanup(root) }
        let engine = NoteSearchSpotlight(store: store, storageRoot: root)
        #expect(engine.kind == .spotlight)
    }
}
