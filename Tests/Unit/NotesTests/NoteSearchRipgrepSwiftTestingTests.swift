// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("NoteSearchRipgrep", .serialized)
struct NoteSearchRipgrepSwiftTestingTests {

    private static let workspaceID = NoteWorkspaceID(
        workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/rg-notes")
    )

    private func makeStore() -> (NoteStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "cocxy-search-ripgrep-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        return (NoteStore(storageRoot: root, format: .markdown), root)
    }

    @Test("noteID parses UUID markdown filenames from ripgrep paths")
    func noteIDParsesMarkdownFilename() throws {
        let id = try #require(UUID(uuidString: "4C83A6F4-463C-4D72-84FE-1D2441B108B8"))
        let path = "/tmp/\(id.uuidString).md"

        #expect(NoteSearchRipgrep.noteID(from: path) == id)
    }

    @Test("parseMatches decodes ripgrep json match events")
    func parseMatchesDecodesJSON() throws {
        let id = try #require(UUID(uuidString: "4C83A6F4-463C-4D72-84FE-1D2441B108B8"))
        let json = """
        {"type":"begin","data":{"path":{"text":"/tmp/\(id.uuidString).md"}}}
        {"type":"match","data":{"path":{"text":"/tmp/\(id.uuidString).md"},"lines":{"text":"alpha needle beta\\n"},"submatches":[{"match":{"text":"needle"},"start":6,"end":12}]}}
        {"type":"end","data":{"path":{"text":"/tmp/\(id.uuidString).md"},"stats":{"matches":1}}}
        """

        let matches = NoteSearchRipgrep.parseMatches(from: Data(json.utf8))

        #expect(matches == [
            NoteSearchRipgrep.RipgrepMatch(
                path: "/tmp/\(id.uuidString).md",
                preview: "alpha needle beta",
                matchCount: 1
            ),
        ])
    }

    @Test("search uses bundled rg when available and returns note results")
    func searchUsesBundledExecutable() async throws {
        let rg = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources")
            .appendingPathComponent("rg")
        #expect(FileManager.default.isExecutableFile(atPath: rg.path))

        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = try await store.create(
            in: Self.workspaceID,
            body: "# Ripgrep Note\nneedle appears twice needle"
        )
        _ = try await store.create(in: Self.workspaceID, body: "unrelated")
        let engine = NoteSearchRipgrep(store: store, executableURL: rg)

        let hits = try await engine.search(query: "needle", in: Self.workspaceID)

        #expect(hits.map(\.noteID) == [saved.id])
        #expect(hits.first?.title == "Ripgrep Note")
        #expect(hits.first?.preview.contains("needle") == true)
    }

    @Test("search falls back to grep when the executable is unavailable")
    func searchFallsBackWhenExecutableMissing() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = try await store.create(in: Self.workspaceID, body: "fallback needle")
        let engine = NoteSearchRipgrep(store: store, executableURL: nil)

        let hits = try await engine.search(query: "needle", in: Self.workspaceID)

        #expect(hits.map(\.noteID) == [saved.id])
    }
}
