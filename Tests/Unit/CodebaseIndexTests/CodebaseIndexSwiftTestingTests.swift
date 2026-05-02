// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodebaseIndexSwiftTestingTests.swift - Local-only codebase indexing foundation.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CodebaseIndex")
struct CodebaseIndexSwiftTestingTests {

    @Test("lexical fallback ranks local code results and respects ignore policies")
    func lexicalFallbackRanksLocalCodeResultsAndRespectsIgnorePolicies() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try "*.log\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "Generated/\n".write(to: root.appendingPathComponent(".cocxyindexignore"), atomically: true, encoding: .utf8)
        try "private=1\n".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "session restoration ignored\n".write(to: root.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        try "session restoration generated\n".write(
            to: root.appendingPathComponent("Generated/Session.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        struct SessionRestorer {
            func restoreSessionSnapshot() {}
            // session restoration keeps tabs and panes together
        }
        """.write(to: root.appendingPathComponent("Sources/SessionRestorer.swift"), atomically: true, encoding: .utf8)
        try "restoration notes\n".write(to: root.appendingPathComponent("Notes.md"), atomically: true, encoding: .utf8)

        let index = CodebaseIndex(workspace: AgentWorkspace(rootURL: root))
        let response = try index.search(CodebaseSearchRequest(query: "session restoration", limit: 10))

        #expect(response.mode == .lexicalFallback)
        #expect(response.results.first?.path == "Sources/SessionRestorer.swift")
        #expect(response.results.first?.line == 3)
        #expect(response.results.map(\.path).contains("Notes.md"))
        #expect(!response.results.map(\.path).contains("Generated/Session.swift"))
        #expect(!response.results.map(\.path).contains("debug.log"))
        #expect(!response.results.map(\.path).contains(".env"))
    }

    @Test("lexical fallback scopes search to a validated workspace subdirectory")
    func lexicalFallbackScopesSearchToValidatedWorkspaceSubdirectory() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try "target inside\n".write(to: root.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try "target outside\n".write(to: root.appendingPathComponent("Tests/AppTests.swift"), atomically: true, encoding: .utf8)

        let index = CodebaseIndex(workspace: AgentWorkspace(rootURL: root))
        let response = try index.search(CodebaseSearchRequest(query: "target", scopePath: "Sources", limit: 10))

        #expect(response.results.map(\.path) == ["Sources/App.swift"])
        #expect(throws: AgentWorkspaceError.outsideRoot("../outside")) {
            _ = try index.search(CodebaseSearchRequest(query: "target", scopePath: "../outside", limit: 10))
        }
    }

    @Test("file chunker splits large text deterministically")
    func fileChunkerSplitsLargeTextDeterministically() {
        let chunker = CodebaseFileChunker(maxChunkBytes: 22)

        let chunks = chunker.chunks(for: "alpha beta\ngamma delta\nlast\n", path: "Sources/App.swift")

        #expect(chunks.map(\.path) == ["Sources/App.swift", "Sources/App.swift"])
        #expect(chunks.map(\.startLine) == [1, 3])
        #expect(chunks.first?.text == "alpha beta\ngamma delta")
        #expect(chunks.last?.text == "last")
    }

    @Test("Merkle snapshot detects changed and removed files")
    func merkleSnapshotDetectsChangedAndRemovedFiles() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("Sources/App.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let builder = CodebaseMerkleTreeBuilder(workspace: AgentWorkspace(rootURL: root))
        let first = try builder.snapshot()
        try "let value = 2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let second = try builder.snapshot()
        try FileManager.default.removeItem(at: fileURL)
        let third = try builder.snapshot()

        #expect(first.changedFiles(comparedTo: nil) == ["Sources/App.swift"])
        #expect(second.changedFiles(comparedTo: first) == ["Sources/App.swift"])
        #expect(third.removedFiles(comparedTo: second) == ["Sources/App.swift"])
    }

    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-codebase-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Tests", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Generated", isDirectory: true),
            withIntermediateDirectories: true
        )
        return root
    }
}
