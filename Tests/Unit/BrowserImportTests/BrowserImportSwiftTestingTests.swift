// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportSwiftTestingTests.swift - Browser import domain coverage.

import Foundation
import SQLite3
import Testing
@testable import CocxyTerminal

@Suite("BrowserImport")
struct BrowserImportSwiftTestingTests {

    @Test("supported sources expose common browser default locations")
    func supportedSourcesExposeDefaultLocations() {
        let sources = BrowserImportSource.allCases

        #expect(sources.count >= 8)
        #expect(sources.contains(.chrome))
        #expect(sources.contains(.firefox))
        #expect(sources.contains(.safari))
        #expect(BrowserImportSource.arc.defaultLocations(homeDirectory: URL(fileURLWithPath: "/Users/me")).contains {
            $0.historyPath.path.contains("Arc")
        })
    }

    @Test("plan applies whitelist and blacklist before importing URLs")
    func planFiltersDomains() {
        let plan = BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            domainWhitelist: ["example.com"],
            domainBlacklist: ["blocked.example.com"]
        )

        #expect(plan.allows(urlString: "https://docs.example.com/path"))
        #expect(!plan.allows(urlString: "https://blocked.example.com/path"))
        #expect(!plan.allows(urlString: "https://other.test"))
    }

    @Test("chromium importer reads history and cookies from profile database files")
    func chromiumImporterReadsHistoryAndCookies() throws {
        let fixture = try BrowserImportFixture.chromium()
        let plan = BrowserImportPlan(
            source: .chrome,
            profileID: UUID(),
            explicitLocations: [
                BrowserImportLocation(
                    source: .chrome,
                    profileName: "Default",
                    historyPath: fixture.history,
                    cookiesPath: fixture.cookies,
                    bookmarksPath: nil
                ),
            ]
        )

        let result = try ChromiumBrowserImporter().preview(plan: plan)

        #expect(result.history.count == 1)
        #expect(result.history[0].url == "https://example.com/docs")
        #expect(result.cookies.count == 1)
        #expect(result.cookies[0].name == "session")
        #expect(result.errors.isEmpty)
    }

    @Test("firefox importer reads places and cookies sqlite files")
    func firefoxImporterReadsPlacesAndCookies() throws {
        let fixture = try BrowserImportFixture.firefox()
        let plan = BrowserImportPlan(
            source: .firefox,
            profileID: UUID(),
            explicitLocations: [
                BrowserImportLocation(
                    source: .firefox,
                    profileName: "default-release",
                    historyPath: fixture.history,
                    cookiesPath: fixture.cookies,
                    bookmarksPath: nil
                ),
            ]
        )

        let result = try FirefoxBrowserImporter().preview(plan: plan)

        #expect(result.history.map(\.url) == ["https://mozilla.example/start"])
        #expect(result.cookies.map(\.domain) == [".mozilla.example"])
        #expect(result.errors.isEmpty)
    }

    @Test("safari importer reads history database and fails soft for cookie files")
    func safariImporterReadsHistoryAndSkipsUnsupportedCookies() throws {
        let fixture = try BrowserImportFixture.safari()
        let plan = BrowserImportPlan(
            source: .safari,
            profileID: UUID(),
            explicitLocations: [
                BrowserImportLocation(
                    source: .safari,
                    profileName: "Safari",
                    historyPath: fixture.history,
                    cookiesPath: fixture.cookies,
                    bookmarksPath: nil
                ),
            ]
        )

        let result = try SafariBrowserImporter().preview(plan: plan)

        #expect(result.history.map(\.url) == ["https://webkit.example/history"])
        #expect(result.cookies.isEmpty)
        #expect(result.errors.contains { $0.message.contains("Cookies.binarycookies") })
    }

    @Test("orchestrator imports profile-scoped history and bookmarks with audit entries")
    func orchestratorImportsIntoStoresAndAudit() throws {
        let profileID = UUID()
        let historyStore = try SQLiteBrowserHistoryStore(databasePath: ":memory:")
        let bookmarkStore = InMemoryBrowserImportBookmarkStore()
        let cookieStore = InMemoryBrowserImportCookieStore()
        let auditLogger = InMemoryBrowserImportAuditLogger()
        let importer = BrowserImporter(
            sourceImporter: StubBrowserSourceImporter(previewResult: BrowserImportPreview(
                history: [
                    BrowserImportedHistoryVisit(
                        url: "https://example.com/imported",
                        title: "Imported",
                        visitedAt: Date()
                    ),
                ],
                cookies: [
                    BrowserImportedCookie(
                        domain: ".example.com",
                        name: "session",
                        path: "/",
                        value: "abc",
                        expiresAt: nil,
                        isSecure: true,
                        isHTTPOnly: true
                    ),
                ],
                bookmarks: [
                    BrowserImportedBookmark(title: "Imported Bookmark", url: "https://example.com/bookmark"),
                ],
                errors: []
            )),
            historyStore: historyStore,
            bookmarkStore: bookmarkStore,
            cookieStore: cookieStore,
            auditLogger: auditLogger
        )

        let result = try importer.importData(BrowserImportPlan(source: .chrome, profileID: profileID))

        #expect(result.importedHistoryCount == 1)
        #expect(result.importedCookieCount == 1)
        #expect(result.importedBookmarkCount == 1)
        #expect(try historyStore.recentHistory(profileID: profileID, limit: 10).count == 1)
        #expect(try bookmarkStore.loadAll().first?.title == "Imported Bookmark")
        #expect(cookieStore.cookies.first?.domain == ".example.com")
        #expect(auditLogger.entries.count == 1)
    }
}

private enum BrowserImportFixture {
    struct SQLitePair {
        let history: URL
        let cookies: URL
    }

    static func chromium() throws -> SQLitePair {
        let root = try temporaryDirectory("chromium")
        let history = root.appendingPathComponent("History")
        let cookies = root.appendingPathComponent("Cookies")
        try createDatabase(history, statements: [
            "CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT NOT NULL, title TEXT, last_visit_time INTEGER NOT NULL)",
            "INSERT INTO urls(id, url, title, last_visit_time) VALUES (1, 'https://example.com/docs', 'Docs', 13359571200000000)",
        ])
        try createDatabase(cookies, statements: [
            "CREATE TABLE cookies(host_key TEXT, name TEXT, path TEXT, value TEXT, encrypted_value BLOB, expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER)",
            "INSERT INTO cookies(host_key, name, path, value, encrypted_value, expires_utc, is_secure, is_httponly) VALUES ('.example.com', 'session', '/', 'abc', X'', 0, 1, 1)",
        ])
        return SQLitePair(history: history, cookies: cookies)
    }

    static func firefox() throws -> SQLitePair {
        let root = try temporaryDirectory("firefox")
        let history = root.appendingPathComponent("places.sqlite")
        let cookies = root.appendingPathComponent("cookies.sqlite")
        try createDatabase(history, statements: [
            "CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT NOT NULL, title TEXT, last_visit_date INTEGER)",
            "INSERT INTO moz_places(id, url, title, last_visit_date) VALUES (1, 'https://mozilla.example/start', 'Start', 1770000000000000)",
        ])
        try createDatabase(cookies, statements: [
            "CREATE TABLE moz_cookies(host TEXT, name TEXT, path TEXT, value TEXT, expiry INTEGER, isSecure INTEGER, isHttpOnly INTEGER)",
            "INSERT INTO moz_cookies(host, name, path, value, expiry, isSecure, isHttpOnly) VALUES ('.mozilla.example', 'sid', '/', 'fire', 0, 1, 0)",
        ])
        return SQLitePair(history: history, cookies: cookies)
    }

    static func safari() throws -> SQLitePair {
        let root = try temporaryDirectory("safari")
        let history = root.appendingPathComponent("History.db")
        let cookies = root.appendingPathComponent("Cookies.binarycookies")
        try createDatabase(history, statements: [
            "CREATE TABLE history_items(id INTEGER PRIMARY KEY, url TEXT NOT NULL, title TEXT)",
            "CREATE TABLE history_visits(id INTEGER PRIMARY KEY, history_item INTEGER NOT NULL, visit_time REAL NOT NULL)",
            "INSERT INTO history_items(id, url, title) VALUES (1, 'https://webkit.example/history', 'History')",
            "INSERT INTO history_visits(id, history_item, visit_time) VALUES (1, 1, 764294400)",
        ])
        try Data("unsupported".utf8).write(to: cookies)
        return SQLitePair(history: history, cookies: cookies)
    }

    private static func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-browser-import-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func createDatabase(_ url: URL, statements: [String]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw BrowserImportFixtureError.databaseOpen
        }
        defer { sqlite3_close(db) }
        for statement in statements {
            guard sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK else {
                throw BrowserImportFixtureError.statementFailed(statement)
            }
        }
    }
}

private enum BrowserImportFixtureError: Error {
    case databaseOpen
    case statementFailed(String)
}

private final class InMemoryBrowserImportCookieStore: BrowserImportedCookieStoring, @unchecked Sendable {
    private(set) var cookies: [BrowserImportedCookie] = []

    func saveImportedCookie(_ cookie: BrowserImportedCookie, profileID: UUID) throws {
        cookies.append(cookie)
    }
}

private final class InMemoryBrowserImportBookmarkStore: BrowserBookmarkStoring, @unchecked Sendable {
    private var bookmarks: [BrowserBookmark] = []

    func loadAll() throws -> [BrowserBookmark] {
        bookmarks
    }

    func save(_ bookmark: BrowserBookmark) throws {
        bookmarks.append(bookmark)
    }

    func update(_ bookmark: BrowserBookmark) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index] = bookmark
    }

    func delete(id: UUID) throws {
        bookmarks.removeAll { $0.id == id }
    }

    func move(id: UUID, toParent: UUID?, sortOrder: Int) throws {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].parentID = toParent
        bookmarks[index].sortOrder = sortOrder
    }

    func search(query: String) -> [BrowserBookmark] {
        bookmarks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    func children(of parentID: UUID?) -> [BrowserBookmark] {
        bookmarks.filter { $0.parentID == parentID }
    }
}

private final class InMemoryBrowserImportAuditLogger: BrowserImportAuditLogging, @unchecked Sendable {
    private(set) var entries: [BrowserImportAuditEntry] = []

    func record(_ entry: BrowserImportAuditEntry) throws {
        entries.append(entry)
    }
}

private struct StubBrowserSourceImporter: BrowserSourceImporting {
    let previewResult: BrowserImportPreview

    func preview(plan: BrowserImportPlan) throws -> BrowserImportPreview {
        previewResult
    }
}
