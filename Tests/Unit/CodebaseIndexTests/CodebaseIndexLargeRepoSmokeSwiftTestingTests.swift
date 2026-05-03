// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodebaseIndexLargeRepoSmokeSwiftTestingTests.swift - Opt-in large repo smoke for semantic codebase indexing.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CodebaseIndexLargeRepoSmoke")
struct CodebaseIndexLargeRepoSmokeSwiftTestingTests {
    @Test("large repo semantic smoke indexes current checkout when explicitly enabled")
    func largeRepoSemanticSmokeIndexesCurrentCheckoutWhenEnabled() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["COCXY_ENABLE_LARGE_REPO_SMOKE"] == "1" else {
            return
        }

        let rootPath = environment["COCXY_CODEBASE_SMOKE_ROOT"] ?? FileManager.default.currentDirectoryPath
        let maxFiles = Self.integerEnvironmentValue("COCXY_CODEBASE_SMOKE_MAX_FILES", defaultValue: 10_000)
        let maxChunks = Self.integerEnvironmentValue("COCXY_CODEBASE_SMOKE_MAX_CHUNKS", defaultValue: 12_000)
        let minimumFiles = Self.integerEnvironmentValue(
            "COCXY_CODEBASE_SMOKE_MIN_FILES",
            defaultValue: min(1_000, maxFiles)
        )
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let workspace = AgentWorkspace(rootURL: rootURL)
        let provider = Self.embeddingProvider(
            named: environment["COCXY_CODEBASE_SMOKE_PROVIDER"] ?? "local-code-token"
        )
        #expect(provider.isAvailable)
        guard provider.isAvailable else {
            return
        }

        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-codebase-large-smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storageURL) }

        let semanticIndex = CodebaseSemanticIndex(
            workspace: workspace,
            store: CodebaseVectorStore(storageURL: storageURL),
            embeddingProvider: provider,
            chunker: CodebaseFileChunker(maxChunkBytes: 8_192),
            maxFileBytes: 512_000,
            maxIndexedFiles: maxFiles,
            maxIndexedChunks: maxChunks
        )

        let rebuildStartedAt = Date()
        let stats = try semanticIndex.rebuild()
        let rebuildSeconds = Date().timeIntervalSince(rebuildStartedAt)

        let searchStartedAt = Date()
        let results = try semanticIndex.search(query: "agent codebase search", limit: 5)
        let searchSeconds = Date().timeIntervalSince(searchStartedAt)

        print(
            "CODEBASE_INDEX_LARGE_SMOKE " +
            "indexed_files=\(stats.indexedFiles) " +
            "indexed_chunks=\(stats.indexedChunks) " +
            "truncated=\(stats.truncated) " +
            "provider=\(provider.identifier) " +
            "max_files=\(maxFiles) " +
            "max_chunks=\(maxChunks) " +
            "rebuild_seconds=\(String(format: "%.3f", rebuildSeconds)) " +
            "search_seconds=\(String(format: "%.3f", searchSeconds)) " +
            "top_paths=\(results.map(\.path).joined(separator: ","))"
        )

        #expect(stats.indexedFiles >= minimumFiles)
        #expect(stats.indexedChunks >= stats.indexedFiles)
        #expect(rebuildSeconds < 300)
        #expect(searchSeconds < 5)
        #expect(!results.isEmpty)
    }

    private static func integerEnvironmentValue(_ name: String, defaultValue: Int) -> Int {
        guard let rawValue = ProcessInfo.processInfo.environment[name],
              let value = Int(rawValue)
        else {
            return defaultValue
        }
        return max(1, value)
    }

    private static func embeddingProvider(named name: String) -> any CodebaseEmbeddingProviding {
        switch name {
        case "natural-language":
            return NaturalLanguageCodebaseEmbeddingProvider()
        default:
            return LocalCodeTokenEmbeddingProvider()
        }
    }
}
