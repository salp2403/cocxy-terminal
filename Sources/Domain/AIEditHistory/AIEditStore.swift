// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditStore.swift - Append-only JSONL storage for local edit history.

import Foundation

enum AIEditStoreError: Error, Equatable, Sendable {
    case invalidIdentifier(String)
}

struct AIEditStore {
    let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/ai-edits-history", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    func append(_ record: AIEditRecord, repoID: String) throws {
        try validate(repoID)
        try validate(record.sessionID)
        let fileURL = try historyFileURL(repoID: repoID, sessionID: record.sessionID)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(record)
        data.append(0x0A)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    }

    func load(repoID: String, sessionID: String) throws -> [AIEditRecord] {
        let fileURL = try historyFileURL(repoID: repoID, sessionID: sessionID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { try decoder.decode(AIEditRecord.self, from: Data($0.utf8)) }
    }

    func timeline(repoID: String, sessionID: String) throws -> AIEditTimeline {
        AIEditTimeline(records: try load(repoID: repoID, sessionID: sessionID))
    }

    func delete(repoID: String, sessionID: String) throws {
        let fileURL = try historyFileURL(repoID: repoID, sessionID: sessionID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    func historyFileURL(repoID: String, sessionID: String) throws -> URL {
        try validate(repoID)
        try validate(sessionID)
        return rootDirectory
            .appendingPathComponent(repoID, isDirectory: true)
            .appendingPathComponent("\(sessionID).jsonl")
    }

    private func validate(_ identifier: String) throws {
        guard identifier.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#, options: .regularExpression) != nil,
              !identifier.contains("..") else {
            throw AIEditStoreError.invalidIdentifier(identifier)
        }
    }
}
