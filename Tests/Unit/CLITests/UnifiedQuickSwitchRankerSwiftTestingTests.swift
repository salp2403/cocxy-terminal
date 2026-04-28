// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// UnifiedQuickSwitchRankerSwiftTestingTests.swift - Pure ranker coverage.

import Foundation
import Testing
import CocxyShared

@Suite("Unified QuickSwitch ranker")
struct UnifiedQuickSwitchRankerSwiftTestingTests {
    private let now = Date(timeIntervalSince1970: 1_800)

    @Test("empty query ranks by priority, recency, then kind bias")
    func emptyQueryRanksByBaseScore() {
        let items = [
            item("browser", kind: .browserTab, title: "Docs", lastUsedSecondsAgo: 10, priority: 0),
            item("tab", kind: .tab, title: "Agent", lastUsedSecondsAgo: 30, priority: 0),
            item("note", kind: .note, title: "Scratch", lastUsedSecondsAgo: 5, priority: 100),
        ]
        let ranked = UnifiedQuickSwitchRanker.rank(query: "", items: items, now: now)
        #expect(ranked.map { $0.item.id } == ["note", "tab", "browser"])
    }

    @Test("exact title match beats substring and fuzzy matches")
    func exactMatchWins() {
        let ranked = UnifiedQuickSwitchRanker.rank(query: "main", items: [
            item("a", kind: .worktree, title: "maintenance"),
            item("b", kind: .tab, title: "main"),
            item("c", kind: .browserTab, title: "mail inbox"),
        ], now: now)
        #expect(ranked.first?.item.id == "b")
    }

    @Test("keywords participate in search")
    func keywordsParticipate() {
        let ranked = UnifiedQuickSwitchRanker.rank(query: "review", items: [
            item("tab", kind: .tab, title: "project", keywords: ["pull request review"]),
            item("browser", kind: .browserTab, title: "localhost"),
        ], now: now)
        #expect(ranked.map { $0.item.id } == ["tab"])
    }

    @Test("normalization ignores punctuation and case")
    func normalizationIgnoresPunctuation() {
        #expect(UnifiedQuickSwitchRanker.normalize("My-Project_v2") == "myprojectv2")
    }

    @Test("no fuzzy match returns no items")
    func noMatchReturnsEmpty() {
        let ranked = UnifiedQuickSwitchRanker.rank(query: "zzzz", items: [
            item("tab", kind: .tab, title: "main"),
        ], now: now)
        #expect(ranked.isEmpty)
    }

    @Test("tie falls back to kind bias")
    func tieFallsBackToKindBias() {
        let ranked = UnifiedQuickSwitchRanker.rank(query: "project", items: [
            item("note", kind: .note, title: "project"),
            item("worktree", kind: .worktree, title: "project"),
        ], now: now)
        #expect(ranked.first?.item.id == "worktree")
    }

    private func item(
        _ id: String,
        kind: UnifiedQuickSwitchItemKind,
        title: String,
        keywords: [String] = [],
        lastUsedSecondsAgo: TimeInterval? = nil,
        priority: Int = 0
    ) -> UnifiedQuickSwitchItem {
        UnifiedQuickSwitchItem(
            id: id,
            kind: kind,
            title: title,
            keywords: keywords,
            lastUsedAt: lastUsedSecondsAgo.map { now.addingTimeInterval(-$0) },
            priority: priority
        )
    }
}
