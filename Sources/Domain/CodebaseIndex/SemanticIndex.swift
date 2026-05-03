// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SemanticIndex.swift - Local semantic codebase indexing orchestration.

import CryptoKit
import Foundation

struct CodebaseSemanticIndexStats: Sendable, Equatable {
    let indexedFiles: Int
    let indexedChunks: Int
    let removedPaths: Int
    let truncated: Bool
}

struct CodebaseSemanticIndex {
    let workspace: AgentWorkspace
    let store: CodebaseVectorStore
    let embeddingProvider: any CodebaseEmbeddingProviding
    let chunker: CodebaseFileChunker
    let maxFileBytes: Int
    let maxIndexedFiles: Int
    let maxIndexedChunks: Int

    init(
        workspace: AgentWorkspace,
        store: CodebaseVectorStore,
        embeddingProvider: any CodebaseEmbeddingProviding,
        chunker: CodebaseFileChunker = CodebaseFileChunker(),
        maxFileBytes: Int = 1_000_000,
        maxIndexedFiles: Int = 2_000,
        maxIndexedChunks: Int = 4_000
    ) {
        self.workspace = workspace
        self.store = store
        self.embeddingProvider = embeddingProvider
        self.chunker = chunker
        self.maxFileBytes = maxFileBytes
        self.maxIndexedFiles = max(1, maxIndexedFiles)
        self.maxIndexedChunks = max(1, maxIndexedChunks)
    }

    static func localDefault(
        workspace: AgentWorkspace,
        maxFileBytes: Int = 1_000_000
    ) -> CodebaseSemanticIndex? {
        let provider = NaturalLanguageCodebaseEmbeddingProvider()
        guard provider.isAvailable else {
            return nil
        }
        return CodebaseSemanticIndex(
            workspace: workspace,
            store: CodebaseVectorStore(storageURL: defaultStorageURL(for: workspace)),
            embeddingProvider: provider,
            maxFileBytes: maxFileBytes
        )
    }

    static func defaultStorageURL(for workspace: AgentWorkspace) -> URL {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let digest = SHA256.hash(data: Data(workspace.rootURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return baseURL
            .appendingPathComponent("dev.cocxy.codebase-index", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
    }

    func rebuildIfNeeded() throws -> CodebaseSemanticIndexStats? {
        guard try store.recordCount() == 0 else {
            return nil
        }
        return try rebuild()
    }

    func rebuild() throws -> CodebaseSemanticIndexStats {
        guard embeddingProvider.isAvailable else {
            throw CodebaseEmbeddingProviderError.providerUnavailable(embeddingProvider.identifier)
        }

        let scanner = CodebaseIndexFileScanner(workspace: workspace, maxFileBytes: maxFileBytes)
        var indexedFiles = 0
        var records: [CodebaseVectorRecord] = []
        var truncated = false

        for file in scanner.regularFiles(startingAt: workspace.rootURL) {
            guard indexedFiles < maxIndexedFiles, records.count < maxIndexedChunks else {
                truncated = true
                break
            }
            guard let content = try? scanner.readTextFile(file) else {
                continue
            }
            let chunks = chunker.chunks(for: content, path: file.relativePath)
            let chunkRecords = try recordsForChunks(chunks)
            guard !chunkRecords.isEmpty else {
                continue
            }
            indexedFiles += 1
            let remainingChunkCapacity = maxIndexedChunks - records.count
            if chunkRecords.count > remainingChunkCapacity {
                records.append(contentsOf: chunkRecords.prefix(remainingChunkCapacity))
                truncated = true
                break
            }
            records.append(contentsOf: chunkRecords)
        }

        try store.replaceAll(records)
        return CodebaseSemanticIndexStats(
            indexedFiles: indexedFiles,
            indexedChunks: records.count,
            removedPaths: 0,
            truncated: truncated
        )
    }

    func update(changes: CodebaseIndexChangeSet) throws -> CodebaseSemanticIndexStats {
        guard embeddingProvider.isAvailable else {
            throw CodebaseEmbeddingProviderError.providerUnavailable(embeddingProvider.identifier)
        }

        let stalePaths = Set(changes.changedFiles + changes.removedFiles)
        try store.remove(paths: stalePaths)

        let scanner = CodebaseIndexFileScanner(workspace: workspace, maxFileBytes: maxFileBytes)
        var indexedFiles = 0
        var records: [CodebaseVectorRecord] = []
        var truncated = false

        for path in changes.changedFiles {
            guard indexedFiles < maxIndexedFiles, records.count < maxIndexedChunks else {
                truncated = true
                break
            }
            guard let content = try? scanner.readTextFile(relativePath: path) else {
                continue
            }
            let chunks = chunker.chunks(for: content, path: path)
            let chunkRecords = try recordsForChunks(chunks)
            guard !chunkRecords.isEmpty else {
                continue
            }
            indexedFiles += 1
            let remainingChunkCapacity = maxIndexedChunks - records.count
            if chunkRecords.count > remainingChunkCapacity {
                records.append(contentsOf: chunkRecords.prefix(remainingChunkCapacity))
                truncated = true
                break
            }
            records.append(contentsOf: chunkRecords)
        }

        try store.upsert(records)
        return CodebaseSemanticIndexStats(
            indexedFiles: indexedFiles,
            indexedChunks: records.count,
            removedPaths: stalePaths.count,
            truncated: truncated
        )
    }

    func search(query: String, scopePath: String? = nil, limit: Int) throws -> [CodebaseSearchResult] {
        guard embeddingProvider.isAvailable else {
            throw CodebaseEmbeddingProviderError.providerUnavailable(embeddingProvider.identifier)
        }

        let queryEmbedding = try embeddingProvider.embedding(for: query)
        let vectorResults = try store.search(
            embedding: queryEmbedding,
            limit: limit,
            pathPrefix: normalizedScopePrefix(scopePath)
        )

        return vectorResults.filter { $0.score > 0 }.map { result in
            CodebaseSearchResult(
                path: result.record.path,
                line: result.record.startLine,
                preview: preview(for: result.record),
                score: result.score,
                matchKind: .content
            )
        }
    }

    private func recordsForChunks(_ chunks: [CodebaseFileChunk]) throws -> [CodebaseVectorRecord] {
        try chunks.compactMap { chunk in
            let embedding: [Double]
            do {
                embedding = try embeddingProvider.embedding(for: chunk.text)
            } catch let error as CodebaseEmbeddingProviderError {
                switch error {
                case .emptyInput, .emptyEmbedding:
                    return nil
                case .providerUnavailable, .nonFiniteEmbedding:
                    throw error
                }
            }
            guard !embedding.isEmpty else {
                return nil
            }
            return CodebaseVectorRecord(
                path: chunk.path,
                startLine: chunk.startLine,
                endLine: chunk.endLine,
                text: chunk.text,
                embedding: embedding
            )
        }
    }

    private func normalizedScopePrefix(_ scopePath: String?) -> String? {
        guard let scopePath,
              !scopePath.isEmpty,
              scopePath != "."
        else {
            return nil
        }
        return scopePath
    }

    private func preview(for record: CodebaseVectorRecord) -> String {
        record.text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? record.path
    }
}
