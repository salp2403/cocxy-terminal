// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityStore.swift - SQLite persistence for local-only activity data.

import Foundation
import SQLite3

protocol ActivityStoring: AnyObject {
    func recordEvent(_ event: ActivityEvent) throws
    func recordTokenUsage(_ record: TokenUsageRecord) throws
    func events(matching query: ActivityStoreQuery) throws -> [ActivityEvent]
    func tokenUsage(matching query: ActivityStoreQuery) throws -> [TokenUsageRecord]
    func deleteAll() throws
}

enum ActivityStoreError: Error, Equatable, LocalizedError {
    case databaseOpenFailed(String)
    case statementPrepareFailed(String)
    case executionFailed(String)
    case metadataEncodingFailed(String)
    case metadataDecodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseOpenFailed(let message):
            return "Activity database open failed: \(message)"
        case .statementPrepareFailed(let message):
            return "Activity database statement failed: \(message)"
        case .executionFailed(let message):
            return "Activity database execution failed: \(message)"
        case .metadataEncodingFailed(let message):
            return "Activity metadata encoding failed: \(message)"
        case .metadataDecodingFailed(let message):
            return "Activity metadata decoding failed: \(message)"
        }
    }
}

final class SQLiteActivityStore: ActivityStoring, @unchecked Sendable {
    private var database: OpaquePointer?
    private let queue = DispatchQueue(label: "com.cocxy.activity-store", qos: .utility)
    private let metadataEncoder: JSONEncoder
    private let metadataDecoder: JSONDecoder

    init(databasePath: String = SQLiteActivityStore.defaultDatabaseURL().path) throws {
        self.metadataEncoder = JSONEncoder()
        self.metadataEncoder.outputFormatting = [.sortedKeys]
        self.metadataDecoder = JSONDecoder()

        if databasePath != ":memory:" {
            let databaseURL = URL(fileURLWithPath: databasePath)
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databasePath, &db, flags, nil)

        guard result == SQLITE_OK, let openedDB = db else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(db)
            throw ActivityStoreError.databaseOpenFailed(message)
        }

        self.database = openedDB
        try enableWALModeIfNeeded(databasePath: databasePath)
        try createTables()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    static func defaultDatabaseURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent(".config/cocxy/activity", isDirectory: true)
            .appendingPathComponent("activity.sqlite")
    }

    func recordEvent(_ event: ActivityEvent) throws {
        try queue.sync {
            let statement = try prepareStatement("""
                INSERT INTO activity_events (
                    id, timestamp, kind, session_id, project_id, project_name, summary, metadata_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, event.id.uuidString, -1, Self.sqliteTransient)
            sqlite3_bind_double(statement, 2, event.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 3, event.kind.rawValue, -1, Self.sqliteTransient)
            bindOptionalText(event.sessionID, to: statement, index: 4)
            bindOptionalText(event.project?.id, to: statement, index: 5)
            bindOptionalText(event.project?.name, to: statement, index: 6)
            sqlite3_bind_text(statement, 7, event.summary, -1, Self.sqliteTransient)
            sqlite3_bind_text(
                statement,
                8,
                try encodedMetadata(event.metadata),
                -1,
                Self.sqliteTransient
            )

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ActivityStoreError.executionFailed(lastErrorMessage)
            }
        }
    }

    func recordTokenUsage(_ record: TokenUsageRecord) throws {
        try queue.sync {
            let statement = try prepareStatement("""
                INSERT INTO token_usage (
                    id, timestamp, provider, model, session_id, project_id, project_name,
                    input_tokens, output_tokens, cost_micros
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, record.id.uuidString, -1, Self.sqliteTransient)
            sqlite3_bind_double(statement, 2, record.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 3, record.provider, -1, Self.sqliteTransient)
            sqlite3_bind_text(statement, 4, record.model, -1, Self.sqliteTransient)
            bindOptionalText(record.sessionID, to: statement, index: 5)
            bindOptionalText(record.project?.id, to: statement, index: 6)
            bindOptionalText(record.project?.name, to: statement, index: 7)
            sqlite3_bind_int64(statement, 8, Int64(record.inputTokens))
            sqlite3_bind_int64(statement, 9, Int64(record.outputTokens))
            sqlite3_bind_int64(statement, 10, record.estimatedCostMicros)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ActivityStoreError.executionFailed(lastErrorMessage)
            }
        }
    }

    func events(matching query: ActivityStoreQuery = ActivityStoreQuery()) throws -> [ActivityEvent] {
        try queue.sync {
            let selection = Self.selectionSQL(for: query)
            let statement = try prepareStatement("""
                SELECT id, timestamp, kind, session_id, project_id, project_name, summary, metadata_json
                FROM activity_events
                \(selection.whereClause)
                ORDER BY timestamp ASC, id ASC
                """)
            defer { sqlite3_finalize(statement) }
            bindSelection(selection.bindings, to: statement)
            return try readEvents(from: statement)
        }
    }

    func tokenUsage(
        matching query: ActivityStoreQuery = ActivityStoreQuery()
    ) throws -> [TokenUsageRecord] {
        try queue.sync {
            let selection = Self.selectionSQL(for: query)
            let statement = try prepareStatement("""
                SELECT id, timestamp, provider, model, session_id, project_id, project_name,
                       input_tokens, output_tokens, cost_micros
                FROM token_usage
                \(selection.whereClause)
                ORDER BY timestamp ASC, id ASC
                """)
            defer { sqlite3_finalize(statement) }
            bindSelection(selection.bindings, to: statement)
            return readTokenUsage(from: statement)
        }
    }

    func deleteAll() throws {
        try queue.sync {
            try executeInQueue("DELETE FROM activity_events")
            try executeInQueue("DELETE FROM token_usage")
        }
    }

    private func enableWALModeIfNeeded(databasePath: String) throws {
        guard databasePath != ":memory:" else { return }
        try execute("PRAGMA journal_mode=WAL")
    }

    private func createTables() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS activity_events (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                kind TEXT NOT NULL,
                session_id TEXT,
                project_id TEXT,
                project_name TEXT,
                summary TEXT NOT NULL,
                metadata_json TEXT NOT NULL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS token_usage (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                provider TEXT NOT NULL,
                model TEXT NOT NULL,
                session_id TEXT,
                project_id TEXT,
                project_name TEXT,
                input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                cost_micros INTEGER NOT NULL
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_activity_events_timestamp ON activity_events(timestamp)")
        try execute("CREATE INDEX IF NOT EXISTS idx_activity_events_project ON activity_events(project_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_token_usage_timestamp ON token_usage(timestamp)")
        try execute("CREATE INDEX IF NOT EXISTS idx_token_usage_project ON token_usage(project_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_token_usage_provider_model ON token_usage(provider, model)")
    }

    private func prepareStatement(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let prepared = statement else {
            throw ActivityStoreError.statementPrepareFailed(lastErrorMessage)
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
            throw ActivityStoreError.executionFailed(message)
        }
    }

    private func bindOptionalText(_ value: String?, to statement: OpaquePointer, index: Int32) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private enum SQLBinding {
        case double(Double)
        case string(String)
    }

    private static func selectionSQL(for query: ActivityStoreQuery) -> (
        whereClause: String,
        bindings: [SQLBinding]
    ) {
        var clauses: [String] = []
        var bindings: [SQLBinding] = []
        if let dateInterval = query.dateInterval {
            clauses.append("timestamp >= ? AND timestamp <= ?")
            bindings.append(.double(dateInterval.start.timeIntervalSince1970))
            bindings.append(.double(dateInterval.end.timeIntervalSince1970))
        }
        if let projectID = query.projectID {
            clauses.append("project_id = ?")
            bindings.append(.string(projectID))
        }
        if let sessionID = query.sessionID {
            clauses.append("session_id = ?")
            bindings.append(.string(sessionID))
        }

        return (
            clauses.isEmpty ? "" : "WHERE \(clauses.joined(separator: " AND "))",
            bindings
        )
    }

    private func bindSelection(_ bindings: [SQLBinding], to statement: OpaquePointer) {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch binding {
            case .double(let value):
                sqlite3_bind_double(statement, index, value)
            case .string(let value):
                sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
            }
        }
    }

    private func readEvents(from statement: OpaquePointer) throws -> [ActivityEvent] {
        var events: [ActivityEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let idRaw = textColumn(statement, index: 0) ?? ""
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            let kindRaw = textColumn(statement, index: 2) ?? ""
            let sessionID = textColumn(statement, index: 3)
            let projectID = textColumn(statement, index: 4)
            let projectName = textColumn(statement, index: 5)
            let summary = textColumn(statement, index: 6) ?? ""
            let metadataJSON = textColumn(statement, index: 7) ?? "{}"

            guard let id = UUID(uuidString: idRaw),
                  let kind = ActivityEventKind(rawValue: kindRaw) else {
                continue
            }

            let project = projectID.flatMap { id -> ActivityProjectRef? in
                guard let projectName else { return nil }
                return ActivityProjectRef(id: id, name: projectName)
            }

            events.append(ActivityEvent(
                id: id,
                timestamp: timestamp,
                kind: kind,
                sessionID: sessionID,
                project: project,
                summary: summary,
                metadata: try decodedMetadata(metadataJSON)
            ))
        }
        return events
    }

    private func readTokenUsage(from statement: OpaquePointer) -> [TokenUsageRecord] {
        var records: [TokenUsageRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let idRaw = textColumn(statement, index: 0) ?? ""
            guard let id = UUID(uuidString: idRaw) else { continue }

            let projectID = textColumn(statement, index: 5)
            let projectName = textColumn(statement, index: 6)
            let project = projectID.flatMap { id -> ActivityProjectRef? in
                guard let projectName else { return nil }
                return ActivityProjectRef(id: id, name: projectName)
            }

            records.append(TokenUsageRecord(
                id: id,
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                provider: textColumn(statement, index: 2) ?? "",
                model: textColumn(statement, index: 3) ?? "",
                sessionID: textColumn(statement, index: 4),
                project: project,
                inputTokens: Int(sqlite3_column_int64(statement, 7)),
                outputTokens: Int(sqlite3_column_int64(statement, 8)),
                estimatedCostMicros: sqlite3_column_int64(statement, 9)
            ))
        }
        return records
    }

    private func encodedMetadata(_ metadata: [String: String]) throws -> String {
        do {
            let data = try metadataEncoder.encode(metadata)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            throw ActivityStoreError.metadataEncodingFailed(error.localizedDescription)
        }
    }

    private func decodedMetadata(_ text: String) throws -> [String: String] {
        do {
            return try metadataDecoder.decode([String: String].self, from: Data(text.utf8))
        } catch {
            throw ActivityStoreError.metadataDecodingFailed(error.localizedDescription)
        }
    }

    private func textColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    private var lastErrorMessage: String {
        database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
