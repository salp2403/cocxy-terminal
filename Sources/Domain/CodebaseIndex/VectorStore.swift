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

    func remove(paths: Set<String>) throws {
        guard !paths.isEmpty else { return }
        let records = try loadRecords().filter { !paths.contains($0.path) }
        try saveRecords(records)
    }

    func remove(paths: [String]) throws {
        try remove(paths: Set(paths))
    }

    func search(embedding queryEmbedding: [Double], limit: Int) throws -> [CodebaseVectorSearchResult] {
        guard !queryEmbedding.isEmpty, limit > 0 else { return [] }
        try validateFinite(embedding: queryEmbedding, id: "query")

        let clampedLimit = min(limit, 50)
        return try loadRecords()
            .compactMap { record in
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
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
