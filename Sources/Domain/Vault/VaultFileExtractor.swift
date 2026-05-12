// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultFileExtractor.swift - Tolerant local session id extraction from agent state files.

import Foundation
import SQLite3

public enum VaultFileExtractor {
    private static let sessionKeys: Set<String> = [
        "session_id",
        "sessionid",
        "conversation_id",
        "conversationid",
        "current_session",
        "currentsession",
        "resume_session",
        "resumesession",
    ]

    private static let timestampKeys: [String] = [
        "updated_at",
        "updatedat",
        "last_seen_at",
        "lastseenat",
        "last_used_at",
        "lastusedat",
        "created_at",
        "createdat",
        "timestamp",
        "time",
    ]

    public static func extractSessionID(fromFileAt url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "sqlite", "sqlite3", "db":
            return extractSessionIDFromSQLite(at: url)
        default:
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8) else {
                return nil
            }
            return extractSessionID(fromContent: content)
        }
    }

    public static func extractSessionID(fromContent content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let jsonSessionID = extractSessionIDFromJSONPayload(trimmed) {
            return jsonSessionID
        }

        var candidates: [String] = []
        for line in trimmed.split(whereSeparator: \.isNewline) {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if let sessionID = extractSessionIDFromJSONPayload(text) {
                candidates.append(sessionID)
                continue
            }

            if let sessionID = extractSessionIDFromKeyValueLine(text) {
                candidates.append(sessionID)
            }
        }

        return candidates.last
    }

    private static func extractSessionIDFromJSONPayload(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return sessionIDs(in: object).last
    }

    private static func sessionIDs(in object: Any) -> [String] {
        if let dictionary = object as? [String: Any] {
            var matches: [String] = []
            for (key, value) in dictionary {
                if isSessionKey(key), let string = normalizedSessionID(value) {
                    matches.append(string)
                }
                matches.append(contentsOf: sessionIDs(in: value))
            }
            return matches
        }

        if let array = object as? [Any] {
            return array.flatMap(sessionIDs(in:))
        }

        return []
    }

    private static func extractSessionIDFromKeyValueLine(_ line: String) -> String? {
        guard let separator = line.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
            return nil
        }
        let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSessionKey(key) else { return nil }

        let value = String(line[line.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return normalizedSessionID(value)
    }

    private static func normalizedSessionID(_ value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func isSessionKey(_ key: String) -> Bool {
        let normalized = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        return sessionKeys.contains(normalized)
    }

    private static func extractSessionIDFromSQLite(at url: URL) -> String? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }

        for table in sqliteTables(database) {
            let columns = sqliteColumns(in: table, database: database)
            let sessionColumns = columns.filter { isSessionKey($0) }
            guard !sessionColumns.isEmpty else { continue }

            let orderColumn = timestampKeys.first { wanted in
                columns.contains { column in
                    column.lowercased().replacingOccurrences(of: "-", with: "_") == wanted
                }
            }

            for column in sessionColumns {
                if let sessionID = sqliteFirstSessionID(
                    database: database,
                    table: table,
                    column: column,
                    orderColumn: orderColumn
                ) {
                    return sessionID
                }
            }
        }

        return nil
    }

    private static func sqliteTables(_ database: OpaquePointer) -> [String] {
        sqliteStrings(
            database,
            sql: """
            SELECT name
            FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """
        )
    }

    private static func sqliteColumns(in table: String, database: OpaquePointer) -> [String] {
        sqliteStrings(database, sql: "PRAGMA table_info(\(quoteIdentifier(table)))", columnIndex: 1)
    }

    private static func sqliteFirstSessionID(
        database: OpaquePointer,
        table: String,
        column: String,
        orderColumn: String?
    ) -> String? {
        let quotedColumn = quoteIdentifier(column)
        var sql = """
        SELECT \(quotedColumn)
        FROM \(quoteIdentifier(table))
        WHERE \(quotedColumn) IS NOT NULL
          AND length(trim(CAST(\(quotedColumn) AS TEXT))) > 0
        """
        if let orderColumn {
            sql += " ORDER BY \(quoteIdentifier(orderColumn)) DESC"
        }
        sql += " LIMIT 1"

        return sqliteStrings(database, sql: sql).first
    }

    private static func sqliteStrings(
        _ database: OpaquePointer,
        sql: String,
        columnIndex: Int32 = 0
    ) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(statement) }

        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, columnIndex) else { continue }
            let value = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                values.append(value)
            }
        }
        return values
    }

    private static func quoteIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
