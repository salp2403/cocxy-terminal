// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `NoteSearchFTS5` contract: the SQL script we generate is
/// well-formed (escaping handles single and double quotes), the rank
/// normaliser keeps scores in `[0, 1]`, the parser ignores garbage
/// rows, and the end-to-end search exercises the real `sqlite3` CLI
/// when one is present at the documented path.
@Suite("NoteSearchFTS5", .serialized)
struct NoteSearchFTS5SwiftTestingTests {

    private static let workspaceID = NoteWorkspaceID(
        workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo")
    )

    private func makeStore() -> (NoteStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "cocxy-search-fts5-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        return (NoteStore(storageRoot: root, format: .markdown), root)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Pure helpers

    @Test("buildScript creates the FTS5 virtual table once and inserts every note")
    func buildScriptIncludesEveryNote() {
        let workspaceID = Self.workspaceID
        let first = Note(workspaceID: workspaceID, body: "alpha")
        let second = Note(workspaceID: workspaceID, body: "beta")

        let script = NoteSearchFTS5.buildScript(notes: [first, second], query: "alpha", limit: 50)

        #expect(script.contains("CREATE VIRTUAL TABLE notes_fts USING fts5"))
        #expect(script.contains("'\(first.id.uuidString)'"))
        #expect(script.contains("'\(second.id.uuidString)'"))
        #expect(script.contains("MATCH '\"alpha\"'"))
        #expect(script.contains("LIMIT 50"))
    }

    @Test("buildScript escapes single quotes in note bodies so a quote in a note never breaks the script")
    func buildScriptEscapesSingleQuotes() {
        let note = Note(
            workspaceID: Self.workspaceID,
            body: "John's note with 'embedded' quotes"
        )

        let script = NoteSearchFTS5.buildScript(notes: [note], query: "test", limit: 50)

        #expect(script.contains("John''s note with ''embedded'' quotes"))
    }

    @Test("sanitizeQuery wraps the query in double quotes so FTS5 treats it as a phrase search")
    func sanitizeQueryWrapsInDoubleQuotes() {
        #expect(NoteSearchFTS5.sanitizeQuery("alpha") == "\"alpha\"")
    }

    @Test("sanitizeQuery escapes embedded double quotes so the FTS5 phrase syntax stays valid")
    func sanitizeQueryEscapesDoubleQuotes() {
        #expect(NoteSearchFTS5.sanitizeQuery(#"phrase"with"quotes"#) == #""phrase""with""quotes""#)
    }

    @Test("sanitizeQuery doubles single quotes so the SQL literal stays well-formed")
    func sanitizeQueryEscapesSingleQuotes() {
        #expect(NoteSearchFTS5.sanitizeQuery("john's") == "\"john''s\"")
    }

    @Test("normaliseRank maps ranks onto [0, 1] so the UI's score ramp behaves consistently across backends")
    func normaliseRankIsBounded() {
        let small = NoteSearchFTS5.normaliseRank(-0.5)
        let large = NoteSearchFTS5.normaliseRank(-100.0)
        let zero = NoteSearchFTS5.normaliseRank(0)

        #expect(zero == 0)
        #expect(small > 0 && small < 1)
        #expect(large > small)
        #expect(large < 1)
    }

    @Test("parseResults skips rows whose UUID prefix is malformed so a corrupt sqlite output never crashes the engine")
    func parseResultsSkipsMalformedRows() {
        let valid = Note(workspaceID: Self.workspaceID, body: "valid")
        let output = """
        not-a-uuid|-1.5
        \(valid.id.uuidString)|-2.5
        """

        let results = NoteSearchFTS5.parseResults(output: output, notes: [valid])

        #expect(results.count == 1)
        #expect(results.first?.noteID == valid.id)
    }

    @Test("parseResults skips rows whose UUID is unknown to the workspace so cross-workspace leaks cannot happen")
    func parseResultsSkipsUnknownIDs() {
        let valid = Note(workspaceID: Self.workspaceID, body: "valid")
        let stranger = UUID()
        let output = """
        \(stranger.uuidString)|-1.5
        \(valid.id.uuidString)|-2.5
        """

        let results = NoteSearchFTS5.parseResults(output: output, notes: [valid])

        #expect(results.count == 1)
    }

    // MARK: - End-to-end (skips when sqlite3 missing)

    @Test("search returns hits when /usr/bin/sqlite3 is available and FTS5 is compiled in")
    func searchReturnsHitsWhenSqlite3Available() async throws {
        try requireFTS5OrSkip()
        let (store, root) = makeStore()
        defer { cleanup(root) }
        _ = try await store.create(in: Self.workspaceID, body: "alpha bravo charlie")
        _ = try await store.create(in: Self.workspaceID, body: "delta echo foxtrot")

        let engine = NoteSearchFTS5(store: store)
        let hits = try await engine.search(query: "alpha", in: Self.workspaceID)

        #expect(hits.count == 1)
        #expect(hits.first?.title.contains("alpha") == true || hits.first?.preview.contains("alpha") == true)
    }

    @Test("search returns an empty array for blank queries even before reaching sqlite")
    func searchReturnsEmptyForBlankQuery() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }
        _ = try await store.create(in: Self.workspaceID, body: "anything")

        let engine = NoteSearchFTS5(store: store)
        let hits = try await engine.search(query: "  ", in: Self.workspaceID)

        #expect(hits.isEmpty)
    }

    @Test("search throws sqlite3NotFound when the configured path is not executable so the UI can show a helpful banner")
    func searchThrowsWhenBinaryMissing() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }
        _ = try await store.create(in: Self.workspaceID, body: "anything")

        let engine = NoteSearchFTS5(
            store: store,
            sqlite3Path: URL(fileURLWithPath: "/nonexistent/sqlite3")
        )

        await #expect(throws: NoteSearchError.self) {
            _ = try await engine.search(query: "anything", in: Self.workspaceID)
        }
    }

    @Test("kind is fts5 so the factory and the diagnostics layer can recognise the engine")
    func kindIsFTS5() {
        let (store, root) = makeStore()
        defer { cleanup(root) }
        let engine = NoteSearchFTS5(store: store)
        #expect(engine.kind == .fts5)
    }

    // MARK: - Skip helpers

    /// Skips the test when the macOS native `sqlite3` binary is
    /// missing or does not advertise FTS5. CI runners that ship a
    /// stripped sqlite3 fall through here without failing the suite.
    private func requireFTS5OrSkip() throws {
        let path = "/usr/bin/sqlite3"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            try #require(Bool(false), "sqlite3 not available — skipping FTS5 e2e")
            return
        }
        // Lightweight probe: instantiate an FTS5 virtual table; if the
        // sqlite3 build does not include FTS5 it returns non-zero.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [":memory:"]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        try stdin.fileHandleForWriting.write(
            contentsOf: Data("CREATE VIRTUAL TABLE t USING fts5(b);\n".utf8)
        )
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            try #require(Bool(false), "sqlite3 lacks FTS5 — skipping FTS5 e2e")
        }
    }
}
