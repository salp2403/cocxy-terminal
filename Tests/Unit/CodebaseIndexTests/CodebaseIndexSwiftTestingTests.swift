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

    @Test("sync service reports incremental changes from Merkle snapshots")
    func syncServiceReportsIncrementalChangesFromSnapshots() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Sources/App.swift")
        let testURL = root.appendingPathComponent("Tests/AppTests.swift")
        try "let value = 1\n".write(to: appURL, atomically: true, encoding: .utf8)

        var emittedChanges: [CodebaseIndexChangeSet] = []
        let service = CodebaseIndexSyncService(workspace: AgentWorkspace(rootURL: root)) {
            emittedChanges.append($0)
        }

        let initial = try service.refresh()
        #expect(initial.changedFiles == ["Sources/App.swift"])
        #expect(initial.removedFiles.isEmpty)

        try "let value = 2\n".write(to: appURL, atomically: true, encoding: .utf8)
        try "func testValue() {}\n".write(to: testURL, atomically: true, encoding: .utf8)
        let changed = try service.handleFileSystemEvent()
        #expect(changed.changedFiles == ["Sources/App.swift", "Tests/AppTests.swift"])
        #expect(changed.removedFiles.isEmpty)

        try FileManager.default.removeItem(at: appURL)
        let removed = try service.handleFileSystemEvent()
        #expect(removed.changedFiles.isEmpty)
        #expect(removed.removedFiles == ["Sources/App.swift"])
        #expect(emittedChanges.map(\.changedFiles) == [
            ["Sources/App.swift", "Tests/AppTests.swift"],
            [],
        ])
        #expect(emittedChanges.map(\.removedFiles) == [
            [],
            ["Sources/App.swift"],
        ])
    }

    @Test("sync service ignores protected and ignored files")
    func syncServiceIgnoresProtectedAndIgnoredFiles() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try "Generated/\n*.log\n".write(to: root.appendingPathComponent(".cocxyindexignore"), atomically: true, encoding: .utf8)
        try "private=1\n".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "ignored\n".write(to: root.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        try "generated\n".write(to: root.appendingPathComponent("Generated/File.swift"), atomically: true, encoding: .utf8)
        try "indexed\n".write(to: root.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)

        let service = CodebaseIndexSyncService(workspace: AgentWorkspace(rootURL: root))
        let initial = try service.refresh()

        #expect(initial.changedFiles == ["Sources/App.swift"])
        #expect(!initial.changedFiles.contains(".env"))
        #expect(!initial.changedFiles.contains("debug.log"))
        #expect(!initial.changedFiles.contains("Generated/File.swift"))
    }

    @Test("vector store persists chunks and ranks by cosine similarity")
    func vectorStorePersistsChunksAndRanksByCosineSimilarity() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent(".cocxy-index", isDirectory: true)
        let store = CodebaseVectorStore(storageURL: storeURL)

        try store.upsert([
            CodebaseVectorRecord(
                path: "Sources/Auth.swift",
                startLine: 1,
                endLine: 8,
                text: "token login session",
                embedding: [1, 0]
            ),
            CodebaseVectorRecord(
                path: "Sources/Theme.swift",
                startLine: 1,
                endLine: 6,
                text: "glass color palette",
                embedding: [0, 1]
            ),
        ])

        let reloaded = CodebaseVectorStore(storageURL: storeURL)
        let results = try reloaded.search(embedding: [0.95, 0.05], limit: 10)

        #expect(results.map(\.record.path) == ["Sources/Auth.swift", "Sources/Theme.swift"])
        #expect(results[0].score > results[1].score)
    }

    @Test("vector store removes stale path chunks")
    func vectorStoreRemovesStalePathChunks() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CodebaseVectorStore(storageURL: root.appendingPathComponent(".cocxy-index", isDirectory: true))
        try store.upsert([
            CodebaseVectorRecord(path: "Sources/App.swift", startLine: 1, endLine: 4, text: "app", embedding: [1, 0]),
            CodebaseVectorRecord(path: "Sources/App.swift", startLine: 5, endLine: 9, text: "app 2", embedding: [1, 0.1]),
            CodebaseVectorRecord(path: "Sources/Other.swift", startLine: 1, endLine: 3, text: "other", embedding: [0, 1]),
        ])

        try store.remove(paths: ["Sources/App.swift"])

        let results = try store.search(embedding: [1, 0], limit: 10)
        #expect(results.map(\.record.path) == ["Sources/Other.swift"])
    }

    @Test("vector store rejects non-finite embeddings")
    func vectorStoreRejectsNonFiniteEmbeddings() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CodebaseVectorStore(storageURL: root.appendingPathComponent(".cocxy-index", isDirectory: true))

        #expect(throws: CodebaseVectorStoreError.nonFiniteEmbedding("Sources/App.swift:1-1")) {
            try store.upsert([
                CodebaseVectorRecord(
                    path: "Sources/App.swift",
                    startLine: 1,
                    endLine: 1,
                    text: "bad",
                    embedding: [.nan]
                ),
            ])
        }
    }

    @Test("vector store returns no results for empty query or zero limit")
    func vectorStoreReturnsNoResultsForEmptyQueryOrZeroLimit() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CodebaseVectorStore(storageURL: root.appendingPathComponent(".cocxy-index", isDirectory: true))
        try store.upsert([
            CodebaseVectorRecord(path: "Sources/App.swift", startLine: 1, endLine: 4, text: "app", embedding: [1, 0]),
        ])

        #expect(try store.search(embedding: [], limit: 10).isEmpty)
        #expect(try store.search(embedding: [1, 0], limit: 0).isEmpty)
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
