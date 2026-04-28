// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// UnifiedQuickSwitch.swift - Pure model and ranker for cross-surface switching.

import Foundation

public enum UnifiedQuickSwitchItemKind: String, Codable, Sendable, Equatable, CaseIterable {
    case tab
    case browserTab
    case worktree
    case note
}

public struct UnifiedQuickSwitchItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: UnifiedQuickSwitchItemKind
    public let title: String
    public let subtitle: String?
    public let keywords: [String]
    public let lastUsedAt: Date?
    public let priority: Int

    public init(
        id: String,
        kind: UnifiedQuickSwitchItemKind,
        title: String,
        subtitle: String? = nil,
        keywords: [String] = [],
        lastUsedAt: Date? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.lastUsedAt = lastUsedAt
        self.priority = priority
    }
}

public struct UnifiedQuickSwitchRankedItem: Sendable, Equatable {
    public let item: UnifiedQuickSwitchItem
    public let score: Int
}

public enum UnifiedQuickSwitchRanker {
    public static func rank(
        query: String,
        items: [UnifiedQuickSwitchItem],
        now: Date = Date()
    ) -> [UnifiedQuickSwitchRankedItem] {
        let normalizedQuery = normalize(query)
        let ranked = items.compactMap { item -> UnifiedQuickSwitchRankedItem? in
            let score: Int
            if normalizedQuery.isEmpty {
                score = baseScore(for: item, now: now)
            } else if let matchScore = bestMatchScore(query: normalizedQuery, item: item) {
                score = matchScore + baseScore(for: item, now: now)
            } else {
                return nil
            }
            return UnifiedQuickSwitchRankedItem(item: item, score: score)
        }

        return ranked.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.item.kind != rhs.item.kind {
                return kindBias(lhs.item.kind) > kindBias(rhs.item.kind)
            }
            return lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title) == .orderedAscending
        }
    }

    private static func bestMatchScore(query: String, item: UnifiedQuickSwitchItem) -> Int? {
        let candidates = [item.title, item.subtitle].compactMap { $0 } + item.keywords
        return candidates.compactMap { candidate in
            score(query: query, candidate: normalize(candidate))
        }.max()
    }

    private static func score(query: String, candidate: String) -> Int? {
        guard candidate.isEmpty == false else { return nil }
        if candidate == query { return 400 }
        if candidate.hasPrefix(query) { return 300 - min(candidate.count - query.count, 80) }
        if candidate.contains(query) { return 220 - min(candidate.count - query.count, 80) }
        return fuzzyScore(query: query, candidate: candidate)
    }

    private static func fuzzyScore(query: String, candidate: String) -> Int? {
        var score = 120
        var searchStart = candidate.startIndex
        var lastIndex: String.Index?
        for character in query {
            guard let found = candidate[searchStart...].firstIndex(of: character) else { return nil }
            if let lastIndex {
                let gap = candidate.distance(from: candidate.index(after: lastIndex), to: found)
                score -= min(gap * 4, 40)
            }
            lastIndex = found
            searchStart = candidate.index(after: found)
        }
        return score
    }

    private static func baseScore(for item: UnifiedQuickSwitchItem, now: Date) -> Int {
        let recencyScore: Int
        if let lastUsedAt = item.lastUsedAt {
            let age = max(0, now.timeIntervalSince(lastUsedAt))
            recencyScore = max(0, 80 - Int(age / 60))
        } else {
            recencyScore = 0
        }
        return item.priority + recencyScore + kindBias(item.kind)
    }

    private static func kindBias(_ kind: UnifiedQuickSwitchItemKind) -> Int {
        switch kind {
        case .tab: return 40
        case .worktree: return 30
        case .browserTab: return 20
        case .note: return 10
        }
    }

    public static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
