// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserSQLiteImportReader.swift - Shared SQLite read helpers for browser import.

import Foundation
import SQLite3

enum BrowserSQLiteImportReader {
    static func readRows<T>(
        databaseURL: URL,
        query: String,
        decode: (OpaquePointer) -> T?
    ) throws -> [T] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            sqlite3_close(db)
            throw BrowserImportError.databaseOpenFailed(message)
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw BrowserImportError.statementFailed(message)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let row = decode(statement) {
                rows.append(row)
            }
        }
        return rows
    }

    static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    static func int64(_ statement: OpaquePointer, _ index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    static func bool(_ statement: OpaquePointer, _ index: Int32) -> Bool {
        sqlite3_column_int(statement, index) != 0
    }

    static func double(_ statement: OpaquePointer, _ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }
}

enum BrowserImportDateConverter {
    static func chromeDate(microsecondsSince1601: Int64) -> Date? {
        guard microsecondsSince1601 > 0 else { return nil }
        let secondsSinceUnixEpoch = Double(microsecondsSince1601) / 1_000_000 - 11_644_473_600
        return Date(timeIntervalSince1970: secondsSinceUnixEpoch)
    }

    static func firefoxDate(microsecondsSince1970: Int64) -> Date? {
        guard microsecondsSince1970 > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(microsecondsSince1970) / 1_000_000)
    }

    static func safariDate(secondsSince2001: Double) -> Date? {
        guard secondsSince2001 > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: secondsSince2001)
    }

    static func unixDate(secondsSince1970: Int64) -> Date? {
        guard secondsSince1970 > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(secondsSince1970))
    }
}
