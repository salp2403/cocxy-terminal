// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSearchModels.swift - Search filters and result models for Vault.

import Foundation

public protocol VaultSearchIndexing {
    func indexSession(_ session: VaultSession) throws
    func removeSession(id: String) throws
    func search(query: String, filters: VaultSearchFilters) throws -> [VaultSearchResult]
    func rebuild() throws
}

public struct VaultSearchFilters: Equatable, Sendable {
    public var agentIDs: Set<VaultAgentID>
    public var since: Date?
    public var until: Date?
    public var pinnedOnly: Bool
    public var pinnedSessionIDs: Set<String>
    public var workspacePath: String?

    public init(
        agentIDs: Set<VaultAgentID> = [],
        since: Date? = nil,
        until: Date? = nil,
        pinnedOnly: Bool = false,
        pinnedSessionIDs: Set<String> = [],
        workspacePath: String? = nil
    ) {
        self.agentIDs = agentIDs
        self.since = since
        self.until = until
        self.pinnedOnly = pinnedOnly
        self.pinnedSessionIDs = pinnedSessionIDs
        self.workspacePath = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct VaultSearchHighlight: Codable, Equatable, Sendable {
    public let field: String
    public let snippet: String
    public let offset: Int
    public let length: Int

    public init(field: String, snippet: String, offset: Int, length: Int) {
        self.field = field
        self.snippet = snippet
        self.offset = offset
        self.length = length
    }
}

public struct VaultSearchResult: Equatable, Sendable {
    public let session: VaultSession
    public let highlights: [VaultSearchHighlight]
    public let relevanceScore: Double

    public init(
        session: VaultSession,
        highlights: [VaultSearchHighlight],
        relevanceScore: Double
    ) {
        self.session = session
        self.highlights = highlights
        self.relevanceScore = relevanceScore
    }
}

public enum VaultSortOrder: String, CaseIterable, Codable, Sendable {
    case mostRecent
    case oldest
    case alphabetical
    case agentThenRecent
    case workspaceThenRecent
}

public enum VaultGroupBy: String, CaseIterable, Codable, Sendable {
    case none
    case agent
    case workspace
    case date
    case pinFirst
}
