// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SnippetManager.swift - Local snippet persistence and expansion lookup.

import Foundation

enum SnippetManagerError: Error, Equatable, Sendable {
    case invalidIdentifier(String)
    case invalidTrigger(String)
    case snippetNotFound(String)
}

struct SnippetStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocxy/snippets.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> [Snippet] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Snippet].self, from: data)
    }

    func save(_ snippets: [Snippet]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snippets.sorted(by: sortSnippets)).write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

struct SnippetManager {
    private let store: SnippetStore
    private let parser: SnippetParser

    init(
        store: SnippetStore = SnippetStore(),
        parser: SnippetParser = SnippetParser()
    ) {
        self.store = store
        self.parser = parser
    }

    func list() throws -> [Snippet] {
        try store.load().sorted(by: sortSnippets)
    }

    func upsert(_ snippet: Snippet) throws {
        try validate(snippet)
        var snippets = try store.load()
        snippets.removeAll { $0.id == snippet.id }
        snippets.append(snippet)
        try store.save(snippets)
    }

    func remove(id: String) throws {
        var snippets = try store.load()
        let originalCount = snippets.count
        snippets.removeAll { $0.id == id }
        guard snippets.count != originalCount else {
            throw SnippetManagerError.snippetNotFound(id)
        }
        try store.save(snippets)
    }

    func snippet(trigger: String, scope: String? = nil) throws -> Snippet? {
        let matches = try list().filter { $0.trigger == trigger }
        if let scope,
           let exact = matches.first(where: { $0.scope == scope }) {
            return exact
        }
        return matches.first { $0.scope == nil }
    }

    func expand(trigger: String, scope: String? = nil) throws -> SnippetExpansion {
        guard let match = try snippet(trigger: trigger, scope: scope) else {
            throw SnippetManagerError.snippetNotFound(trigger)
        }
        return try parser.expand(match.body)
    }

    private func validate(_ snippet: Snippet) throws {
        guard Self.isSafeIdentifier(snippet.id) else {
            throw SnippetManagerError.invalidIdentifier(snippet.id)
        }
        guard !snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !snippet.trigger.contains("\0"),
              !snippet.trigger.contains("\n") else {
            throw SnippetManagerError.invalidTrigger(snippet.trigger)
        }
    }

    private static func isSafeIdentifier(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#, options: .regularExpression) != nil
            && !id.contains("..")
    }
}

private func sortSnippets(_ lhs: Snippet, _ rhs: Snippet) -> Bool {
    if lhs.trigger == rhs.trigger {
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
    return lhs.trigger.localizedStandardCompare(rhs.trigger) == .orderedAscending
}
