// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserSQLiteImportReader.swift - Consistent read-only snapshots of live browser databases.

import Darwin
import Foundation
import SQLite3

enum BrowserSQLiteImportReader {
    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: time_t
        let modifiedNanoseconds: Int
        let changedSeconds: time_t
        let changedNanoseconds: Int

        init(_ metadata: stat) {
            device = metadata.st_dev
            inode = metadata.st_ino
            size = metadata.st_size
            modifiedSeconds = metadata.st_mtimespec.tv_sec
            modifiedNanoseconds = metadata.st_mtimespec.tv_nsec
            changedSeconds = metadata.st_ctimespec.tv_sec
            changedNanoseconds = metadata.st_ctimespec.tv_nsec
        }
    }

    private static let maximumSnapshotFileByteCount: off_t = 2 * 1_024 * 1_024 * 1_024
    private static let maximumSnapshotTotalByteCount: off_t = 2 * 1_024 * 1_024 * 1_024
    private static let snapshotFreeSpaceReserve: Int64 = 64 * 1_024 * 1_024
    private static let maximumTextByteCount = 16 * 1_024
    private static let maximumBlobByteCount = 1 * 1_024 * 1_024
    private static let snapshotSuffixes = ["", "-wal", "-journal"]

    static func readRows<T>(
        databaseURL: URL,
        query: String,
        decode: (OpaquePointer) -> T?
    ) throws -> [T] {
        try withSnapshot(databaseURL: databaseURL) { database in
            try readRows(database: database, query: query, decode: decode)
        }
    }

    static func readRows<T>(
        databaseURL: URL,
        table: String,
        query: (Set<String>) -> String,
        decode: (OpaquePointer) -> T?
    ) throws -> [T] {
        try withSnapshot(databaseURL: databaseURL) { database in
            let columns = try tableColumns(database: database, table: table)
            return try readRows(database: database, query: query(columns), decode: decode)
        }
    }

    static func chromiumCookieDatabaseVersion(databaseURL: URL) throws -> Int? {
        try withSnapshot(databaseURL: databaseURL) { database in
            var statement: OpaquePointer?
            let sql = "SELECT value FROM meta WHERE key = 'version' LIMIT 1"
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                return nil
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            if sqlite3_column_type(statement, 0) == SQLITE_INTEGER {
                return Int(sqlite3_column_int64(statement, 0))
            }
            return text(statement, 0).flatMap(Int.init)
        }
    }

    static func text(
        _ statement: OpaquePointer,
        _ index: Int32,
        maximumByteCount: Int = maximumTextByteCount
    ) -> String? {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count >= 0, count <= maximumByteCount else { return nil }
        if count == 0 {
            return sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : ""
        }
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(
            bytes: UnsafeBufferPointer(start: pointer, count: count),
            encoding: .utf8
        )
    }

    static func blob(
        _ statement: OpaquePointer,
        _ index: Int32,
        maximumByteCount: Int = maximumBlobByteCount
    ) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, count <= maximumByteCount,
              let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: count)
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

    private static func withSnapshot<T>(
        databaseURL: URL,
        body: (OpaquePointer) throws -> T
    ) throws -> T {
        try withCopiedSnapshot(databaseURL: databaseURL, body: body)
    }

    private static func withCopiedSnapshot<T>(
        databaseURL: URL,
        body: (OpaquePointer) throws -> T
    ) throws -> T {
        var lastChangedPath = databaseURL.path
        for attempt in 0..<3 {
            do {
                let directory = try createPrivateSnapshotDirectory()
                defer { try? FileManager.default.removeItem(at: directory) }
                let copiedDatabase = try copyStableSQLiteFiles(
                    databaseURL: databaseURL,
                    destinationDirectory: directory
                )

                var snapshot: OpaquePointer?
                let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
                guard sqlite3_open_v2(copiedDatabase.path, &snapshot, flags, nil) == SQLITE_OK,
                      let snapshot else {
                    let message = snapshot.flatMap { String(cString: sqlite3_errmsg($0)) }
                        ?? "Unable to open private SQLite snapshot"
                    sqlite3_close(snapshot)
                    throw BrowserImportError.databaseOpenFailed(message)
                }
                let copiedSnapshot: OpaquePointer? = snapshot
                defer {
                    if let copiedSnapshot { sqlite3_close(copiedSnapshot) }
                }

                // The first schema read performs hot-journal or WAL recovery on
                // the private copy. query_only prevents later writes. The outer
                // defers close SQLite first and remove the mode-0700 directory
                // immediately after the caller finishes decoding rows.
                try executeSnapshotPragma(snapshot, sql: "PRAGMA schema_version")
                try configureSnapshotForQueries(snapshot)
                return try body(snapshot)
            } catch BrowserImportError.sourceChangedDuringRead(let path) {
                lastChangedPath = path
                if attempt < 2 {
                    sqlite3_sleep(50)
                    continue
                }
            }
        }
        throw BrowserImportError.sourceChangedDuringRead(lastChangedPath)
    }

    private static func copyStableSQLiteFiles(
        databaseURL: URL,
        destinationDirectory: URL
    ) throws -> URL {
        let sourcePaths = snapshotSuffixes.map { databaseURL.path + $0 }
        let initialIdentities = try sourcePaths.map(optionalFileIdentity(path:))
        guard initialIdentities[0] != nil else {
            throw BrowserImportError.invalidSourceFile(databaseURL.path)
        }

        var totalByteCount: off_t = 0
        for (index, identity) in initialIdentities.enumerated() {
            guard let identity else { continue }
            guard identity.size >= 0,
                  identity.size <= maximumSnapshotFileByteCount,
                  totalByteCount <= maximumSnapshotTotalByteCount - identity.size else {
                throw BrowserImportError.invalidSourceFile(sourcePaths[index])
            }
            totalByteCount += identity.size
        }
        try requireSnapshotCapacity(totalByteCount, at: destinationDirectory)

        for (index, identity) in initialIdentities.enumerated() {
            guard let identity else { continue }
            try Task.checkCancellation()
            let destination = destinationDirectory.appendingPathComponent(
                databaseURL.lastPathComponent + snapshotSuffixes[index]
            )
            try copyRegularFile(
                sourcePath: sourcePaths[index],
                destinationPath: destination.path,
                expectedIdentity: identity
            )
        }

        let finalIdentities = try sourcePaths.map(optionalFileIdentity(path:))
        guard finalIdentities == initialIdentities else {
            throw BrowserImportError.sourceChangedDuringRead(databaseURL.path)
        }
        return destinationDirectory.appendingPathComponent(databaseURL.lastPathComponent)
    }

    private static func copyRegularFile(
        sourcePath: String,
        destinationPath: String,
        expectedIdentity: FileIdentity
    ) throws {
        let copied = try BrowserImportFileReader.withRegularFileDescriptor(
            at: URL(fileURLWithPath: sourcePath),
            allowMissing: false
        ) { sourceDescriptor -> Bool in
            var sourceMetadata = stat()
            guard Darwin.fstat(sourceDescriptor, &sourceMetadata) == 0,
                  FileIdentity(sourceMetadata) == expectedIdentity else {
                throw BrowserImportError.sourceChangedDuringRead(sourcePath)
            }

            let destinationDescriptor = destinationPath.withCString {
                Darwin.open(
                    $0,
                    O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                    S_IRUSR | S_IWUSR
                )
            }
            guard destinationDescriptor >= 0 else {
                throw BrowserImportError.databaseOpenFailed(systemError("Create private SQLite snapshot"))
            }
            defer { Darwin.close(destinationDescriptor) }

            var copiedByteCount: off_t = 0
            var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
            while true {
                try Task.checkCancellation()
                let readCount = buffer.withUnsafeMutableBytes { bytes in
                    Darwin.read(sourceDescriptor, bytes.baseAddress, bytes.count)
                }
                if readCount == 0 { break }
                if readCount < 0 {
                    if errno == EINTR { continue }
                    throw BrowserImportError.databaseOpenFailed(systemError("Read SQLite source"))
                }
                guard off_t(readCount) <= expectedIdentity.size - copiedByteCount else {
                    throw BrowserImportError.sourceChangedDuringRead(sourcePath)
                }

                var written = 0
                while written < readCount {
                    let writeCount = buffer.withUnsafeBytes { bytes in
                        Darwin.write(
                            destinationDescriptor,
                            bytes.baseAddress?.advanced(by: written),
                            readCount - written
                        )
                    }
                    if writeCount < 0 {
                        if errno == EINTR { continue }
                        throw BrowserImportError.databaseOpenFailed(systemError("Write private SQLite snapshot"))
                    }
                    written += writeCount
                }
                copiedByteCount += off_t(readCount)
            }

            var finalMetadata = stat()
            guard Darwin.fstat(sourceDescriptor, &finalMetadata) == 0,
                  FileIdentity(finalMetadata) == expectedIdentity,
                  copiedByteCount == expectedIdentity.size else {
                throw BrowserImportError.sourceChangedDuringRead(sourcePath)
            }
            return true
        }
        guard copied == true else {
            throw BrowserImportError.sourceChangedDuringRead(sourcePath)
        }
    }

    private static func requireSnapshotCapacity(_ byteCount: off_t, at directory: URL) throws {
        guard byteCount <= off_t(Int64.max) else {
            throw BrowserImportError.invalidSourceFile(directory.path)
        }
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values?.volumeAvailableCapacityForImportantUsage,
           available < Int64(byteCount) + snapshotFreeSpaceReserve {
            throw BrowserImportError.databaseOpenFailed("Insufficient private snapshot disk capacity")
        }
    }

    private static func createPrivateSnapshotDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-browser-snapshot-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            return directory
        } catch {
            throw BrowserImportError.databaseOpenFailed(
                "Unable to create private SQLite snapshot: \(error.localizedDescription)"
            )
        }
    }

    private static func configureSnapshotForQueries(_ database: OpaquePointer) throws {
        sqlite3_busy_timeout(database, 2_000)
        try executeSnapshotPragma(database, sql: "PRAGMA trusted_schema = OFF")
        try executeSnapshotPragma(database, sql: "PRAGMA query_only = ON")
    }

    private static func executeSnapshotPragma(_ database: OpaquePointer, sql: String) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw BrowserImportError.databaseOpenFailed(
                sqliteFailureMessage(database: database, result: result, operation: sql)
            )
        }
    }

    private static func sqliteFailureMessage(
        database: OpaquePointer,
        result: Int32,
        operation: String
    ) -> String {
        let detail = String(cString: sqlite3_errmsg(database))
        let resultDescription = String(cString: sqlite3_errstr(result))
        return "\(operation) failed (\(resultDescription)): \(detail)"
    }

    private static func systemError(_ operation: String) -> String {
        "\(operation) failed: \(String(cString: strerror(errno)))"
    }

    private static func readRows<T>(
        database: OpaquePointer,
        query: String,
        decode: (OpaquePointer) -> T?
    ) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            let message = String(cString: sqlite3_errmsg(database))
            sqlite3_finalize(statement)
            throw BrowserImportError.statementFailed(message)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [T] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            try Task.checkCancellation()
            if let row = decode(statement) {
                rows.append(row)
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw BrowserImportError.statementFailed(String(cString: sqlite3_errmsg(database)))
        }
        return rows
    }

    private static func tableColumns(database: OpaquePointer, table: String) throws -> Set<String> {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard !table.isEmpty, table.unicodeScalars.allSatisfy(allowed.contains) else {
            throw BrowserImportError.statementFailed("Invalid SQLite table identifier")
        }
        let rows: [String] = try readRows(
            database: database,
            query: "PRAGMA table_info(\(table))"
        ) { statement in
            text(statement, 1)
        }
        guard !rows.isEmpty else {
            throw BrowserImportError.statementFailed("Missing SQLite table: \(table)")
        }
        return Set(rows)
    }

    private static func optionalFileIdentity(path: String) throws -> FileIdentity? {
        try BrowserImportFileReader.withRegularFileDescriptor(
            at: URL(fileURLWithPath: path),
            allowMissing: true
        ) { descriptor in
            var metadata = stat()
            guard Darwin.fstat(descriptor, &metadata) == 0 else {
                throw BrowserImportError.invalidSourceFile(path)
            }
            return FileIdentity(metadata)
        }
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
