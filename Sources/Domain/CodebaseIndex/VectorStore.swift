// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VectorStore.swift - Local vector store for codebase chunk embeddings.

import Foundation

struct CodebaseVectorRecord: Codable, Sendable, Equatable {
    let path: String
    let startLine: Int
    let endLine: Int
    let text: String
    let embedding: [Double]

    var id: String {
        "\(path):\(startLine)-\(endLine)"
    }
}

struct CodebaseVectorSearchResult: Sendable, Equatable {
    let record: CodebaseVectorRecord
    let score: Double
}

enum CodebaseVectorStoreError: Error, Sendable, Equatable {
    case nonFiniteEmbedding(String)
}

struct CodebaseVectorStore: Sendable {
    private let storageURL: URL
    private let fileURL: URL

    init(storageURL: URL) {
        self.storageURL = storageURL.standardizedFileURL
        self.fileURL = self.storageURL.appendingPathComponent("vectors.json")
    }

    func upsert(_ records: [CodebaseVectorRecord]) throws {
        try validateFinite(records)
        var recordsByID = Dictionary(uniqueKeysWithValues: try loadRecords().map { ($0.id, $0) })
        for record in records {
            recordsByID[record.id] = record
        }
        try saveRecords(recordsByID.values.sorted(by: recordSort))
    }

    func replaceAll(_ records: [CodebaseVectorRecord]) throws {
        try validateFinite(records)
        try saveRecords(records)
    }

    func replaceAllStreaming(_ build: (inout CodebaseVectorStoreReplacementWriter) throws -> Void) throws {
        try FileManager.default.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
        let temporaryURL = storageURL.appendingPathComponent("vectors-\(UUID().uuidString).json.tmp")
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: temporaryURL)
        var writer = CodebaseVectorStoreReplacementWriter(fileHandle: fileHandle)

        do {
            try writer.begin()
            try build(&writer)
            try writer.finish()
            try fileHandle.close()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
        } catch {
            try? fileHandle.close()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    func recordCount() throws -> Int {
        try loadRecords().count
    }

    func storageSizeBytes() throws -> Int64 {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return 0
        }
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    func remove(paths: Set<String>) throws {
        guard !paths.isEmpty else { return }
        let records = try loadRecords().filter { !paths.contains($0.path) }
        try saveRecords(records)
    }

    func remove(paths: [String]) throws {
        try remove(paths: Set(paths))
    }

    func search(
        embedding queryEmbedding: [Double],
        limit: Int,
        pathPrefix: String? = nil
    ) throws -> [CodebaseVectorSearchResult] {
        guard !queryEmbedding.isEmpty, limit > 0 else { return [] }
        try validateFinite(embedding: queryEmbedding, id: "query")

        let clampedLimit = min(limit, 50)
        return try loadRecords()
            .compactMap { record in
                guard matchesPathPrefix(record.path, pathPrefix: pathPrefix) else {
                    return nil
                }
                guard record.embedding.count == queryEmbedding.count,
                      let score = cosineSimilarity(queryEmbedding, record.embedding)
                else {
                    return nil
                }
                return CodebaseVectorSearchResult(record: record, score: score)
            }
            .sorted(by: resultSort)
            .prefix(clampedLimit)
            .map { $0 }
    }

    private func loadRecords() throws -> [CodebaseVectorRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([CodebaseVectorRecord].self, from: data)
    }

    private func saveRecords(_ records: [CodebaseVectorRecord]) throws {
        try FileManager.default.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(records.sorted(by: recordSort))
        try data.write(to: fileURL, options: .atomic)
    }

    private func validateFinite(_ records: [CodebaseVectorRecord]) throws {
        for record in records {
            try validateFinite(embedding: record.embedding, id: record.id)
        }
    }

    private func validateFinite(embedding: [Double], id: String) throws {
        guard embedding.allSatisfy(\.isFinite) else {
            throw CodebaseVectorStoreError.nonFiniteEmbedding(id)
        }
    }

    private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        var dot = 0.0
        var lhsMagnitude = 0.0
        var rhsMagnitude = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsMagnitude += lhs[index] * lhs[index]
            rhsMagnitude += rhs[index] * rhs[index]
        }
        guard lhsMagnitude > 0, rhsMagnitude > 0 else {
            return nil
        }
        return dot / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude))
    }

    private func matchesPathPrefix(_ path: String, pathPrefix: String?) -> Bool {
        guard let pathPrefix,
              !pathPrefix.isEmpty,
              pathPrefix != "."
        else {
            return true
        }
        return path == pathPrefix || path.hasPrefix(pathPrefix + "/")
    }

    private func recordSort(_ lhs: CodebaseVectorRecord, _ rhs: CodebaseVectorRecord) -> Bool {
        if lhs.path != rhs.path {
            return lhs.path < rhs.path
        }
        if lhs.startLine != rhs.startLine {
            return lhs.startLine < rhs.startLine
        }
        return lhs.endLine < rhs.endLine
    }

    private func resultSort(_ lhs: CodebaseVectorSearchResult, _ rhs: CodebaseVectorSearchResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return recordSort(lhs.record, rhs.record)
    }
}

struct CodebaseVectorStoreReplacementWriter {
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder
    private(set) var recordCount = 0
    private var hasBegun = false
    private var hasFinished = false

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    mutating func begin() throws {
        guard !hasBegun else { return }
        try fileHandle.write(contentsOf: Data("[\n".utf8))
        hasBegun = true
    }

    mutating func append(_ records: [CodebaseVectorRecord]) throws {
        guard !records.isEmpty else { return }
        guard hasBegun, !hasFinished else { return }
        try validateFinite(records)
        for record in records {
            if recordCount > 0 {
                try fileHandle.write(contentsOf: Data(",\n".utf8))
            }
            let data = try encoder.encode(record)
            try fileHandle.write(contentsOf: data)
            recordCount += 1
        }
    }

    mutating func finish() throws {
        guard hasBegun, !hasFinished else { return }
        try fileHandle.write(contentsOf: Data("\n]\n".utf8))
        hasFinished = true
    }

    private func validateFinite(_ records: [CodebaseVectorRecord]) throws {
        for record in records {
            guard record.embedding.allSatisfy(\.isFinite) else {
                throw CodebaseVectorStoreError.nonFiniteEmbedding(record.id)
            }
        }
    }
}
