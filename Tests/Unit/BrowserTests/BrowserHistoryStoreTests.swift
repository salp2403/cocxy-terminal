// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserHistoryStoreTests.swift - Tests for SQLite-backed browsing history.

import Testing
import Foundation
@testable import CocxyTerminal

// MARK: - Browser History Store Tests

@Suite("SQLiteBrowserHistoryStore")
struct BrowserHistoryStoreTests {

    private let profileA = UUID()
    private let profileB = UUID()

    /// Creates a fresh in-memory history store for each test.
    private func makeStore() throws -> SQLiteBrowserHistoryStore {
        try SQLiteBrowserHistoryStore(databasePath: ":memory:")
    }

    // MARK: - Record Visit

    @Test("Record visit stores entry retrievable via recentHistory")
    func recordVisitIsRetrievable() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://example.com", title: "Example", profileID: profileA)
        let recent = try store.recentHistory(profileID: profileA, limit: 10)

        #expect(recent.count == 1)
        #expect(recent[0].url == "https://example.com")
        #expect(recent[0].title == "Example")
        #expect(recent[0].profileID == profileA)
    }

    @Test("Record visit with nil title stores entry without title")
    func recordVisitNilTitle() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://notitle.com", title: nil, profileID: profileA)
        let recent = try store.recentHistory(profileID: profileA, limit: 10)

        #expect(recent.count == 1)
        #expect(recent[0].title == nil)
    }

    @Test("Multiple visits are stored in chronological order")
    func multipleVisitsOrder() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://first.com", title: "First", profileID: profileA)
        try store.recordVisit(url: "https://second.com", title: "Second", profileID: profileA)
        try store.recordVisit(url: "https://third.com", title: "Third", profileID: profileA)

        let recent = try store.recentHistory(profileID: profileA, limit: 10)

        #expect(recent.count == 3)
        #expect(recent[0].url == "https://third.com")
        #expect(recent[2].url == "https://first.com")
    }

    // MARK: - Search

    @Test("Search finds entries by URL substring")
    func searchByURL() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://swift.org/docs", title: "Swift Docs", profileID: profileA)
        try store.recordVisit(url: "https://github.com", title: "GitHub", profileID: profileA)

        let results = try store.search(query: "swift", profileID: profileA, limit: 10)

        #expect(results.count == 1)
        #expect(results[0].url == "https://swift.org/docs")
    }

    @Test("Search finds entries by title substring")
    func searchByTitle() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://a.com", title: "Swift Documentation", profileID: profileA)
        try store.recordVisit(url: "https://b.com", title: "Rust Handbook", profileID: profileA)

        let results = try store.search(query: "Documentation", profileID: profileA, limit: 10)

        #expect(results.count == 1)
        #expect(results[0].title == "Swift Documentation")
    }

    @Test("Search with empty query returns empty results")
    func searchEmptyQuery() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://example.com", title: "Test", profileID: profileA)
        let results = try store.search(query: "", profileID: profileA, limit: 10)

        #expect(results.isEmpty)
    }

    @Test("Search with whitespace-only query returns empty results")
    func searchWhitespaceQuery() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://example.com", title: "Test", profileID: profileA)
        let results = try store.search(query: "   ", profileID: profileA, limit: 10)

        #expect(results.isEmpty)
    }

    @Test("Search respects limit parameter")
    func searchRespectsLimit() throws {
        let store = try makeStore()

        for i in 0..<5 {
            try store.recordVisit(url: "https://swift\(i).org", title: "Swift \(i)", profileID: profileA)
        }

        let results = try store.search(query: "swift", profileID: profileA, limit: 2)

        #expect(results.count == 2)
    }

    // MARK: - Profile Isolation

    @Test("Visits from profile A are not visible in profile B search")
    func profileIsolationInSearch() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://secret.com", title: "Secret", profileID: profileA)
        try store.recordVisit(url: "https://public.com", title: "Public", profileID: profileB)

        let resultsA = try store.search(query: "Secret", profileID: profileB, limit: 10)

        #expect(resultsA.isEmpty)
    }

    @Test("Recent history filtered by profile only returns that profile")
    func profileIsolationInRecentHistory() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://a.com", title: "Profile A", profileID: profileA)
        try store.recordVisit(url: "https://b.com", title: "Profile B", profileID: profileB)

        let recentA = try store.recentHistory(profileID: profileA, limit: 10)
        let recentB = try store.recentHistory(profileID: profileB, limit: 10)

        #expect(recentA.count == 1)
        #expect(recentA[0].profileID == profileA)
        #expect(recentB.count == 1)
        #expect(recentB[0].profileID == profileB)
    }

    @Test("Recent history with nil profile returns all profiles")
    func recentHistoryAllProfiles() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://a.com", title: "A", profileID: profileA)
        try store.recordVisit(url: "https://b.com", title: "B", profileID: profileB)

        let all = try store.recentHistory(profileID: nil, limit: 10)

        #expect(all.count == 2)
    }

    // MARK: - Recent History

    @Test("Recent history respects limit")
    func recentHistoryRespectsLimit() throws {
        let store = try makeStore()

        for i in 0..<10 {
            try store.recordVisit(url: "https://site\(i).com", title: "Site \(i)", profileID: profileA)
        }

        let recent = try store.recentHistory(profileID: profileA, limit: 3)

        #expect(recent.count == 3)
    }

    // MARK: - Delete by Date Range

    @Test("Delete by date range removes matching entries")
    func deleteByDateRange() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://old.com", title: "Old", profileID: profileA)
        try store.recordVisit(url: "https://new.com", title: "New", profileID: profileA)

        let now = Date()
        let from = now.addingTimeInterval(-1)
        let to = now.addingTimeInterval(1)

        try store.deleteByDateRange(from: from, to: to, profileID: profileA)

        let remaining = try store.recentHistory(profileID: profileA, limit: 10)

        #expect(remaining.isEmpty)
    }

    @Test("Delete by date range with profile filter only affects that profile")
    func deleteByDateRangeProfileFilter() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://a.com", title: "A", profileID: profileA)
        try store.recordVisit(url: "https://b.com", title: "B", profileID: profileB)

        let now = Date()
        try store.deleteByDateRange(
            from: now.addingTimeInterval(-1),
            to: now.addingTimeInterval(1),
            profileID: profileA
        )

        let remainingA = try store.recentHistory(profileID: profileA, limit: 10)
        let remainingB = try store.recentHistory(profileID: profileB, limit: 10)

        #expect(remainingA.isEmpty)
        #expect(remainingB.count == 1)
    }

    // MARK: - Delete All

    @Test("Delete all for a profile clears only that profile")
    func deleteAllForProfile() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://a.com", title: "A", profileID: profileA)
        try store.recordVisit(url: "https://b.com", title: "B", profileID: profileB)

        try store.deleteAll(profileID: profileA)

        let remainingA = try store.recentHistory(profileID: profileA, limit: 10)
        let remainingB = try store.recentHistory(profileID: profileB, limit: 10)

        #expect(remainingA.isEmpty)
        #expect(remainingB.count == 1)
    }

    @Test("Delete all with nil profile clears everything")
    func deleteAllEverything() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://a.com", title: "A", profileID: profileA)
        try store.recordVisit(url: "https://b.com", title: "B", profileID: profileB)

        try store.deleteAll(profileID: nil)

        let all = try store.recentHistory(profileID: nil, limit: 10)

        #expect(all.isEmpty)
    }

    // MARK: - Group by Date

    @Test("groupedByDate returns entries grouped with labels")
    func groupedByDate() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://today.com", title: "Today Visit", profileID: profileA)

        let groups = try store.groupedByDate(profileID: profileA, limit: 10)

        #expect(!groups.isEmpty)
        #expect(groups[0].label == "Today")
        #expect(groups[0].entries.count == 1)
        #expect(groups[0].entries[0].url == "https://today.com")
    }

    @Test("groupedByDate returns empty array when no history")
    func groupedByDateEmpty() throws {
        let store = try makeStore()

        let groups = try store.groupedByDate(profileID: profileA, limit: 10)

        #expect(groups.isEmpty)
    }

    // MARK: - Date Label Helper

    @Test("humanReadableDateLabel returns Today for today")
    func dateLabelToday() {
        let label = SQLiteBrowserHistoryStore.humanReadableDateLabel(for: Date())

        #expect(label == "Today")
    }

    @Test("humanReadableDateLabel returns Yesterday for yesterday")
    func dateLabelYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let label = SQLiteBrowserHistoryStore.humanReadableDateLabel(for: yesterday)

        #expect(label == "Yesterday")
    }

    // MARK: - Database Initialization

    @Test("In-memory database initializes successfully")
    func inMemoryDatabaseInit() throws {
        let store = try makeStore()
        let recent = try store.recentHistory(profileID: nil, limit: 10)

        #expect(recent.isEmpty)
    }

    @Test("Search after deleting all returns empty")
    func searchAfterDeleteAll() throws {
        let store = try makeStore()

        try store.recordVisit(url: "https://findme.com", title: "Find Me", profileID: profileA)
        try store.deleteAll(profileID: nil)

        let results = try store.search(query: "findme", profileID: nil, limit: 10)

        #expect(results.isEmpty)
    }
}
