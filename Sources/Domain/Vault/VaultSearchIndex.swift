// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSearchIndex.swift - Encrypted local full-text index for Vault sessions.

import CryptoKit
import Foundation
import SQLite3

public final class VaultSearchIndex: VaultSearchIndexing {
    public let indexURL: URL
    public let keyProvider: any VaultKeyProviding
    public let fileManager: FileManager

    private var database: OpaquePointer?
    private var documents: [String: VaultSearchDocument] = [:]
    private var isLoaded = false

    private struct Envelope: Codable {
        let version: Int
        let nonce: Data
        let ciphertext: Data
        let tag: Data
    }

    private struct StoredIndex: Codable {
        let version: Int
        let documents: [VaultSearchDocument]
    }

    private struct VaultSearchDocument: Codable {
        let session: VaultSession
        let fields: [Field]

        struct Field: Codable {
            let name: String
            let text: String
        }

        var content: String {
            fields.map(\.text).joined(separator: "\n")
        }
    }

    public init(
        indexURL: URL = VaultSearchIndex.defaultIndexURL(),
        keyProvider: any VaultKeyProviding = VaultFileKeyProvider(),
        fileManager: FileManager = .default
    ) throws {
        self.indexURL = indexURL
        self.keyProvider = keyProvider
        self.fileManager = fileManager
        try openEmptyDatabase()
        try loadPersistedDocumentsIfNeeded()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public static func defaultIndexURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Cocxy Terminal", isDirectory: true)
            .appendingPathComponent("vault-search.sqlite")
    }

    public func indexSession(_ session: VaultSession) throws {
        try loadPersistedDocumentsIfNeeded()
        let document = Self.makeDocument(for: session)
        documents[session.id] = document
        try insertOrReplace(document)
        try savePersistedDocuments()
    }

    public func removeSession(id: String) throws {
        try loadPersistedDocumentsIfNeeded()
        documents.removeValue(forKey: id)
        try execute("DELETE FROM vault_fts WHERE id = ?", bindings: [id])
        try savePersistedDocuments()
    }

    public func search(query: String, filters: VaultSearchFilters) throws -> [VaultSearchResult] {
        try loadPersistedDocumentsIfNeeded()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ftsIDs = try matchingIDsFromFTS(query: trimmedQuery)
        let tokens = Self.searchTokens(from: trimmedQuery)
        let normalizedQuery = Self.normalized(trimmedQuery)

        return documents.values.compactMap { document in
            guard matches(document.session, filters: filters) else { return nil }
            let relevance = relevanceScore(
                document: document,
                tokens: tokens,
                normalizedQuery: normalizedQuery,
                matchedByFTS: ftsIDs.contains(document.session.id)
            )
            guard trimmedQuery.isEmpty || relevance > 0 else { return nil }
            return VaultSearchResult(
                session: document.session,
                highlights: Self.highlights(for: document, tokens: tokens, query: trimmedQuery),
                relevanceScore: relevance
            )
        }
        .sorted { lhs, rhs in
            if lhs.relevanceScore != rhs.relevanceScore {
                return lhs.relevanceScore > rhs.relevanceScore
            }
            if lhs.session.lastSeenAt != rhs.session.lastSeenAt {
                return lhs.session.lastSeenAt > rhs.session.lastSeenAt
            }
            return lhs.session.id < rhs.session.id
        }
    }

    public func rebuild() throws {
        isLoaded = false
        try loadPersistedDocumentsIfNeeded()
        try rebuildDatabase()
    }

    public func rebuild(sessions: [VaultSession]) throws {
        documents = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, Self.makeDocument(for: $0)) })
        isLoaded = true
        try savePersistedDocuments()
        try rebuildDatabase()
    }

    private func loadPersistedDocumentsIfNeeded() throws {
        guard !isLoaded else { return }
        guard fileManager.fileExists(atPath: indexURL.path) else {
            documents = [:]
            isLoaded = true
            try rebuildDatabase()
            return
        }

        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: indexURL))
            let key = SymmetricKey(data: try keyProvider.keyData())
            let sealedBox = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: envelope.nonce),
                ciphertext: envelope.ciphertext,
                tag: envelope.tag
            )
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            let stored = try JSONDecoder().decode(StoredIndex.self, from: plaintext)
            documents = Dictionary(uniqueKeysWithValues: stored.documents.map { ($0.session.id, $0) })
            isLoaded = true
            try rebuildDatabase()
        } catch {
            throw VaultError.corruptStore
        }
    }

    private func savePersistedDocuments() throws {
        try fileManager.createDirectory(
            at: indexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stored = StoredIndex(
            version: 1,
            documents: documents.values.sorted { $0.session.lastSeenAt > $1.session.lastSeenAt }
        )
        let plaintext = try JSONEncoder().encode(stored)
        let key = SymmetricKey(data: try keyProvider.keyData())
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        let envelope = Envelope(
            version: 1,
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: indexURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: indexURL.path)
    }

    private func openEmptyDatabase() throws {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
        guard sqlite3_open(":memory:", &database) == SQLITE_OK else {
            throw currentSQLiteError()
        }
        try execute(
            """
            CREATE VIRTUAL TABLE vault_fts USING fts5(
                id UNINDEXED,
                agent_id UNINDEXED,
                workspace UNINDEXED,
                content,
                tokenize = 'unicode61'
            )
            """
        )
    }

    private func rebuildDatabase() throws {
        try openEmptyDatabase()
        for document in documents.values {
            try insertOrReplace(document)
        }
    }

    private func insertOrReplace(_ document: VaultSearchDocument) throws {
        try execute("DELETE FROM vault_fts WHERE id = ?", bindings: [document.session.id])
        try execute(
            "INSERT INTO vault_fts(id, agent_id, workspace, content) VALUES (?, ?, ?, ?)",
            bindings: [
                document.session.id,
                document.session.agentID.rawValue,
                document.session.workingDirectory ?? "",
                document.content,
            ]
        )
    }

    private func matchingIDsFromFTS(query: String) throws -> Set<String> {
        let tokens = Self.searchTokens(from: query)
        guard !tokens.isEmpty else {
            return Set(documents.keys)
        }

        let ftsQuery = tokens
            .map { token in "\(token)*" }
            .joined(separator: " AND ")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT id FROM vault_fts WHERE vault_fts MATCH ?", -1, &statement, nil) == SQLITE_OK else {
            throw currentSQLiteError()
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, ftsQuery, -1, SQLITE_TRANSIENT)

        var ids = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) {
                ids.insert(String(cString: value))
            }
        }
        return ids
    }

    private func matches(_ session: VaultSession, filters: VaultSearchFilters) -> Bool {
        if !filters.agentIDs.isEmpty, !filters.agentIDs.contains(session.agentID) {
            return false
        }
        if let since = filters.since, session.lastSeenAt < since {
            return false
        }
        if let until = filters.until, session.lastSeenAt > until {
            return false
        }
        if filters.pinnedOnly, !filters.pinnedSessionIDs.contains(session.id) {
            return false
        }
        if let workspacePath = filters.workspacePath, !workspacePath.isEmpty {
            return Self.standardizedPath(session.workingDirectory) == Self.standardizedPath(workspacePath)
        }
        return true
    }

    private func relevanceScore(
        document: VaultSearchDocument,
        tokens: [String],
        normalizedQuery: String,
        matchedByFTS: Bool
    ) -> Double {
        guard !tokens.isEmpty else { return 1 }
        let normalizedContent = Self.normalized(document.content)
        var score = matchedByFTS ? 10.0 : 0.0

        if !normalizedQuery.isEmpty, normalizedContent.contains(normalizedQuery) {
            score += 8
        }

        for token in tokens {
            if normalizedContent.contains(token) {
                score += 3
            } else if Self.isSubsequence(token, of: normalizedContent) {
                score += 0.75
            }
        }

        if document.session.sessionID.localizedCaseInsensitiveContains(normalizedQuery) {
            score += 2
        }
        return score
    }

    private static func makeDocument(for session: VaultSession) -> VaultSearchDocument {
        var fields: [VaultSearchDocument.Field] = [
            .init(name: "agent", text: session.agentDisplayName),
            .init(name: "agentID", text: session.agentID.rawValue),
            .init(name: "sessionID", text: session.sessionID),
            .init(name: "source", text: session.source.rawValue),
            .init(name: "arguments", text: session.sanitizedArguments.joined(separator: " ")),
        ]
        if let workingDirectory = session.workingDirectory, !workingDirectory.isEmpty {
            fields.append(.init(name: "workspace", text: workingDirectory))
            fields.append(.init(name: "workspaceName", text: URL(fileURLWithPath: workingDirectory).lastPathComponent))
        }
        return VaultSearchDocument(session: session, fields: fields)
    }

    private static func highlights(
        for document: VaultSearchDocument,
        tokens: [String],
        query: String
    ) -> [VaultSearchHighlight] {
        guard !tokens.isEmpty || !query.isEmpty else { return [] }
        let needles = tokens.isEmpty ? [normalized(query)] : tokens

        let rankedFields = document.fields
            .filter { !$0.text.isEmpty }
            .map { field -> (field: VaultSearchDocument.Field, matchCount: Int) in
                let lower = field.text.lowercased()
                let count = needles.filter { lower.contains($0) }.count
                return (field, count)
            }
            .sorted { lhs, rhs in lhs.matchCount > rhs.matchCount }

        for candidate in rankedFields where candidate.matchCount > 0 {
            let lower = candidate.field.text.lowercased()
            if let match = needles.compactMap({ lower.range(of: $0) }).first {
                let offset = lower.distance(from: lower.startIndex, to: match.lowerBound)
                let length = lower.distance(from: match.lowerBound, to: match.upperBound)
                let snippet = snippet(from: candidate.field.text, around: offset, length: length)
                let prefixAdjustment = offset > 48 ? 3 : 0
                let snippetOffset = max(0, min(min(offset, 48) + prefixAdjustment, snippet.count))
                return [
                    VaultSearchHighlight(
                        field: candidate.field.name,
                        snippet: snippet,
                        offset: snippetOffset,
                        length: min(length, max(0, snippet.count - snippetOffset))
                    ),
                ]
            }
        }
        return []
    }

    private static func snippet(from text: String, around offset: Int, length: Int) -> String {
        let radius = 48
        let start = max(0, offset - radius)
        let end = min(text.count, offset + length + radius)
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        let prefix = start > 0 ? "..." : ""
        let suffix = end < text.count ? "..." : ""
        return prefix + String(text[startIndex..<endIndex]) + suffix
    }

    private static func searchTokens(from query: String) -> [String] {
        normalized(query)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var remainder = needle[...]
        for character in haystack where character == remainder.first {
            remainder.removeFirst()
            if remainder.isEmpty { return true }
        }
        return false
    }

    private static func standardizedPath(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return NSString(string: value).standardizingPath
    }

    private func execute(_ sql: String, bindings: [String] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw currentSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw currentSQLiteError()
        }
    }

    private func currentSQLiteError() -> NSError {
        let message = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "SQLite error"
        return NSError(domain: "dev.cocxy.terminal.vault.search", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
