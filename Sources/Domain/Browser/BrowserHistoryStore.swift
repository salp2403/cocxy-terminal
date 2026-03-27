// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserHistoryStore.swift - SQLite-backed browsing history with full-text search.

import Foundation
import SQLite3

// MARK: - History Entry

/// A single visit record in the browsing history.
struct HistoryEntry: Identifiable, Sendable {

    /// Row ID from the SQLite database.
    let id: Int64

    /// The URL that was visited.
    let url: String

    /// The page title at the time of the visit.
    let title: String?

    /// When the visit occurred.
    let timestamp: Date

    /// The profile that recorded this visit.
    let profileID: UUID
}

// MARK: - Date Group

/// Groups entries by date for display in a sectioned list.
struct DateGroup<T>: Identifiable, Sendable where T: Sendable {

    /// Identifier derived from the date string.
    let id: String

    /// The calendar date for this group.
    let date: Date

    /// Human-readable label (e.g., "Today", "Yesterday", "25 March").
    let label: String

    /// Entries in this group, sorted by timestamp descending.
    let entries: [T]
}

// MARK: - History Storing Protocol

/// Contract for browsing history persistence and search.
///
/// Implementations must handle concurrent access safely.
/// The default implementation uses SQLite with FTS5 for full-text search.
///
/// - SeeAlso: ``SQLiteBrowserHistoryStore``
protocol BrowserHistoryStoring: Sendable {

    /// Records a new page visit.
    ///
    /// - Parameters:
    ///   - url: The visited URL.
    ///   - title: The page title (may be nil).
    ///   - profileID: The profile that owns this visit.
    func recordVisit(url: String, title: String?, profileID: UUID) throws

    /// Searches history using full-text search on URL and title.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - profileID: Filter by profile. Nil returns all profiles.
    ///   - limit: Maximum number of results.
    /// - Returns: Matching history entries, ordered by relevance.
    func search(query: String, profileID: UUID?, limit: Int) throws -> [HistoryEntry]

    /// Returns the most recent history entries.
    ///
    /// - Parameters:
    ///   - profileID: Filter by profile. Nil returns all profiles.
    ///   - limit: Maximum number of results.
    /// - Returns: Recent entries, ordered by timestamp descending.
    func recentHistory(profileID: UUID?, limit: Int) throws -> [HistoryEntry]

    /// Deletes visits within a date range.
    ///
    /// - Parameters:
    ///   - from: Start of the range (inclusive).
    ///   - to: End of the range (inclusive).
    ///   - profileID: Filter by profile. Nil deletes across all profiles.
    func deleteByDateRange(from: Date, to: Date, profileID: UUID?) throws

    /// Deletes all history entries.
    ///
    /// - Parameter profileID: Filter by profile. Nil deletes everything.
    func deleteAll(profileID: UUID?) throws

    /// Groups recent history entries by date.
    ///
    /// - Parameters:
    ///   - profileID: Filter by profile. Nil returns all profiles.
    ///   - limit: Maximum total entries to fetch before grouping.
    /// - Returns: Entries grouped by calendar date with human-readable labels.
    func groupedByDate(profileID: UUID?, limit: Int) throws -> [DateGroup<HistoryEntry>]
}

// MARK: - History Store Errors

/// Errors from the SQLite history store.
enum BrowserHistoryError: Error, Sendable {
    case databaseOpenFailed(String)
    case statementPrepareFailed(String)
    case executionFailed(String)
}

// MARK: - SQLite History Store

/// SQLite-backed history store with FTS5 full-text search.
///
/// Uses WAL mode for better read concurrency. All database access is
/// serialized through a private dispatch queue to prevent data races.
///
/// ## Schema
///
/// The `visits` table stores raw visit data. The `visits_fts` virtual
/// table provides FTS5 full-text indexing on URL and title columns.
///
/// ## Thread Safety
///
/// All SQLite operations run on a serial queue. The `Sendable`
/// conformance is safe because the queue serializes all mutable state.
///
/// - SeeAlso: ``BrowserHistoryStoring``
final class SQLiteBrowserHistoryStore: BrowserHistoryStoring, @unchecked Sendable {

    // MARK: - Properties

    private var database: OpaquePointer?
    private let queue: DispatchQueue

    // MARK: - Initialization

    /// Creates a history store backed by a SQLite database.
    ///
    /// - Parameter path: Path to the database file. Use ":memory:" for in-memory databases.
    /// - Throws: ``BrowserHistoryError/databaseOpenFailed(_:)`` if the database cannot be opened.
    init(databasePath: String) throws {
        self.queue = DispatchQueue(label: "com.cocxy.browser-history", qos: .userInitiated)

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databasePath, &db, flags, nil)

        guard result == SQLITE_OK, let openedDB = db else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(db)
            throw BrowserHistoryError.databaseOpenFailed(message)
        }

        self.database = openedDB
        try enableWALMode()
        try createTables()
    }

    deinit {
        if let db = database {
            sqlite3_close(db)
        }
    }

    // MARK: - Schema Setup

    private func enableWALMode() throws {
        try execute("PRAGMA journal_mode=WAL")
    }

    private func createTables() throws {
        let createVisits = """
            CREATE TABLE IF NOT EXISTS visits (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                profile_id TEXT NOT NULL,
                url TEXT NOT NULL,
                title TEXT,
                timestamp REAL NOT NULL
            )
            """

        let createFTS = """
            CREATE VIRTUAL TABLE IF NOT EXISTS visits_fts USING fts5(
                url, title, content=visits, content_rowid=id
            )
            """

        let createProfileIndex = """
            CREATE INDEX IF NOT EXISTS idx_visits_profile ON visits(profile_id)
            """

        let createTimestampIndex = """
            CREATE INDEX IF NOT EXISTS idx_visits_timestamp ON visits(timestamp DESC)
            """

        let createInsertTrigger = """
            CREATE TRIGGER IF NOT EXISTS visits_ai AFTER INSERT ON visits BEGIN
                INSERT INTO visits_fts(rowid, url, title) VALUES (new.id, new.url, new.title);
            END
            """

        let createDeleteTrigger = """
            CREATE TRIGGER IF NOT EXISTS visits_ad AFTER DELETE ON visits BEGIN
                INSERT INTO visits_fts(visits_fts, rowid, url, title) VALUES ('delete', old.id, old.url, old.title);
            END
            """

        try execute(createVisits)
        try execute(createFTS)
        try execute(createProfileIndex)
        try execute(createTimestampIndex)
        try execute(createInsertTrigger)
        try execute(createDeleteTrigger)
    }

    // MARK: - BrowserHistoryStoring

    func recordVisit(url: String, title: String?, profileID: UUID) throws {
        try queue.sync {
            let sql = "INSERT INTO visits (profile_id, url, title, timestamp) VALUES (?, ?, ?, ?)"
            let stmt = try prepareStatement(sql)
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, profileID.uuidString, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, url, -1, Self.sqliteTransient)

            if let title {
                sqlite3_bind_text(stmt, 3, title, -1, Self.sqliteTransient)
            } else {
                sqlite3_bind_null(stmt, 3)
            }

            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw BrowserHistoryError.executionFailed(lastErrorMessage)
            }
        }
    }

    func search(query: String, profileID: UUID?, limit: Int) throws -> [HistoryEntry] {
        try queue.sync {
            let sanitizedQuery = sanitizeFTSQuery(query)
            guard !sanitizedQuery.isEmpty else { return [] }

            if let profileID {
                let sql = """
                    SELECT v.id, v.profile_id, v.url, v.title, v.timestamp
                    FROM visits v
                    INNER JOIN visits_fts fts ON v.id = fts.rowid
                    WHERE visits_fts MATCH ? AND v.profile_id = ?
                    ORDER BY fts.rank
                    LIMIT ?
                    """
                let stmt = try prepareStatement(sql)
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, sanitizedQuery, -1, Self.sqliteTransient)
                sqlite3_bind_text(stmt, 2, profileID.uuidString, -1, Self.sqliteTransient)
                sqlite3_bind_int(stmt, 3, Int32(limit))
                return readEntries(from: stmt)
            } else {
                let sql = """
                    SELECT v.id, v.profile_id, v.url, v.title, v.timestamp
                    FROM visits v
                    INNER JOIN visits_fts fts ON v.id = fts.rowid
                    WHERE visits_fts MATCH ?
                    ORDER BY fts.rank
                    LIMIT ?
                    """
                let stmt = try prepareStatement(sql)
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, sanitizedQuery, -1, Self.sqliteTransient)
                sqlite3_bind_int(stmt, 2, Int32(limit))
                return readEntries(from: stmt)
            }
        }
    }

    /// Fetches recent history without acquiring the queue lock.
    /// Caller must already be inside `queue.sync`.
    private func fetchRecentHistory(profileID: UUID?, limit: Int) throws -> [HistoryEntry] {
        let sql: String
        if let profileID {
            sql = """
                SELECT id, profile_id, url, title, timestamp
                FROM visits
                WHERE profile_id = ?
                ORDER BY timestamp DESC
                LIMIT ?
                """
            let stmt = try prepareStatement(sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, profileID.uuidString, -1, Self.sqliteTransient)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            return readEntries(from: stmt)
        } else {
            sql = """
                SELECT id, profile_id, url, title, timestamp
                FROM visits
                ORDER BY timestamp DESC
                LIMIT ?
                """
            let stmt = try prepareStatement(sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            return readEntries(from: stmt)
        }
    }

    func recentHistory(profileID: UUID?, limit: Int) throws -> [HistoryEntry] {
        try queue.sync {
            try fetchRecentHistory(profileID: profileID, limit: limit)
        }
    }

    func deleteByDateRange(from: Date, to: Date, profileID: UUID?) throws {
        try queue.sync {
            if let profileID {
                let sql = """
                    DELETE FROM visits
                    WHERE timestamp >= ? AND timestamp <= ? AND profile_id = ?
                    """
                let stmt = try prepareStatement(sql)
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 3, profileID.uuidString, -1, Self.sqliteTransient)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw BrowserHistoryError.executionFailed(lastErrorMessage)
                }
            } else {
                let sql = """
                    DELETE FROM visits
                    WHERE timestamp >= ? AND timestamp <= ?
                    """
                let stmt = try prepareStatement(sql)
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw BrowserHistoryError.executionFailed(lastErrorMessage)
                }
            }
        }
    }

    func deleteAll(profileID: UUID?) throws {
        try queue.sync {
            if let profileID {
                let sql = "DELETE FROM visits WHERE profile_id = ?"
                let stmt = try prepareStatement(sql)
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, profileID.uuidString, -1, Self.sqliteTransient)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw BrowserHistoryError.executionFailed(lastErrorMessage)
                }
            } else {
                try executeInQueue("DELETE FROM visits")
                try executeInQueue("INSERT INTO visits_fts(visits_fts) VALUES('rebuild')")
            }
        }
    }

    func groupedByDate(profileID: UUID?, limit: Int) throws -> [DateGroup<HistoryEntry>] {
        try queue.sync {
            let entries = try fetchRecentHistory(profileID: profileID, limit: limit)
            return groupEntriesByDate(entries)
        }
    }

    // MARK: - SQLite Helpers

    private func prepareStatement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK,
              let prepared = stmt else {
            throw BrowserHistoryError.statementPrepareFailed(lastErrorMessage)
        }
        return prepared
    }

    private func execute(_ sql: String) throws {
        try queue.sync {
            try executeInQueue(sql)
        }
    }

    private func executeInQueue(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw BrowserHistoryError.executionFailed(message)
        }
    }

    private func readEntries(from stmt: OpaquePointer) -> [HistoryEntry] {
        var entries: [HistoryEntry] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(stmt, 0)

            let profileIDRaw = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let urlRaw = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let titleRaw = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let timestampRaw = sqlite3_column_double(stmt, 4)

            guard let profileUUID = UUID(uuidString: profileIDRaw) else { continue }

            let entry = HistoryEntry(
                id: rowID,
                url: urlRaw,
                title: titleRaw,
                timestamp: Date(timeIntervalSince1970: timestampRaw),
                profileID: profileUUID
            )
            entries.append(entry)
        }

        return entries
    }

    private var lastErrorMessage: String {
        database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
    }

    /// Sanitizes a user query for FTS5.
    ///
    /// Wraps each word in quotes to prevent FTS5 syntax injection.
    /// Empty or whitespace-only queries return an empty string.
    private func sanitizeFTSQuery(_ query: String) -> String {
        let words = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return "" }

        return words
            .map { word -> String in
                let escaped = word.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            .joined(separator: " ")
    }

    /// SQLITE_TRANSIENT equivalent: tells SQLite to copy the string.
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: - Date Grouping

    private func groupEntriesByDate(_ entries: [HistoryEntry]) -> [DateGroup<HistoryEntry>] {
        let calendar = Calendar.current
        var grouped: [String: (date: Date, entries: [HistoryEntry])] = [:]
        var order: [String] = []

        for entry in entries {
            let dayStart = calendar.startOfDay(for: entry.timestamp)
            let key = Self.dateFormatter.string(from: dayStart)

            if grouped[key] == nil {
                grouped[key] = (date: dayStart, entries: [])
                order.append(key)
            }
            grouped[key]?.entries.append(entry)
        }

        return order.compactMap { key in
            guard let group = grouped[key] else { return nil }
            let label = Self.humanReadableDateLabel(for: group.date, calendar: calendar)
            return DateGroup(
                id: key,
                date: group.date,
                label: label,
                entries: group.entries
            )
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let humanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func humanReadableDateLabel(for date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return humanDateFormatter.string(from: date)
        }
    }
}
