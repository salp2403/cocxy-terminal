// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectRegistryStore.swift - Durable project registry file storage.

import Foundation
import os.log

enum ProjectRegistryStoreError: Error, Equatable, CustomStringConvertible {
    case invalidRoot(String)
    case symbolicLinkRejected(String)
    case invalidRecord(String)
    case persistenceFailed(String)

    var description: String {
        switch self {
        case .invalidRoot(let path):
            return "Project registry root is not a directory: \(path)"
        case .symbolicLinkRejected(let path):
            return "Project registry rejected a symbolic link: \(path)"
        case .invalidRecord(let message):
            return "Project registry contains invalid data: \(message)"
        case .persistenceFailed(let message):
            return "Project registry persistence failed: \(message)"
        }
    }
}

struct ProjectRegistryStoreLoadReport: Equatable, Sendable {
    let records: [ProjectRecord]
    let discardedRecords: [ProjectRegistryDiscardedRecord]
    let quarantineFileURL: URL?
    var recoveredWholeDocument = false
    /// The readable records could not be written back to disk.
    var repairFailure: ProjectRegistryStoreError?

    var discardedRecordCount: Int { discardedRecords.count }

    /// Rejected records that were not quarantined still live only in the
    /// unrepaired file, so saving would drop them.
    var allowsPersistence: Bool {
        discardedRecords.isEmpty || quarantineFileURL != nil
    }
}

struct ProjectRegistryDiscardedRecord: Equatable, Sendable {
    let identity: String
    let reason: String
}

struct ProjectRegistryRecoveryDiagnostic: Equatable, Sendable {
    let discardedRecordCount: Int
    let discardedRecordIdentities: [String]
    let discardedRecordReasons: [String]
    let quarantineFileURL: URL
    var recoveredWholeDocument = false
}

struct ProjectRegistryStore: Sendable {
    static let maximumQuarantineFiles = 5
    private static let logger = Logger(
        subsystem: "dev.cocxy.terminal",
        category: "ProjectRegistryStore"
    )

    let fileURL: URL
    private let fileManager: FileManager
    private let atomicWrite: @Sendable (Data, URL) throws -> Void

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/projects/registry.json", isDirectory: false),
        fileManager: FileManager = .default,
        atomicWrite: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.fileManager = fileManager
        self.atomicWrite = atomicWrite
    }

    func load() throws -> [ProjectRecord] {
        try loadReport().records
    }

    func loadReport() throws -> ProjectRegistryStoreLoadReport {
        // A fresh URL: resource values cached by an earlier load must not
        // hide a registry file that was repaired on disk since then.
        let fileURL = URL(fileURLWithPath: self.fileURL.path, isDirectory: false)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ProjectRegistryStoreLoadReport(
                records: [],
                discardedRecords: [],
                quarantineFileURL: nil
            )
        }
        do {
            try validateRoot(createIfMissing: false)
            try rejectSymbolicLink(at: fileURL)
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw ProjectRegistryStoreError.invalidRecord("Registry is not a regular file")
            }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let decodedDocument: Any
            do {
                decodedDocument = try JSONSerialization.jsonObject(with: data)
            } catch {
                return try recoverCorruptDocument(
                    data,
                    reason: "Registry document is not valid JSON"
                )
            }
            guard let rawRecords = decodedDocument as? [Any] else {
                return try recoverCorruptDocument(
                    data,
                    reason: "Registry root must be an array"
                )
            }
            var records: [ProjectRecord] = []
            var discardedRecords: [ProjectRegistryDiscardedRecord] = []
            var discardedRawRecords: [Any] = []
            for (index, rawRecord) in rawRecords.enumerated() {
                do {
                    guard JSONSerialization.isValidJSONObject(rawRecord) else {
                        throw ProjectRegistryStoreError.invalidRecord(
                            "Record \(index + 1) must be a JSON object"
                        )
                    }
                    let recordData = try JSONSerialization.data(withJSONObject: rawRecord)
                    records.append(try Self.decoder.decode(ProjectRecord.self, from: recordData))
                } catch {
                    discardedRawRecords.append(rawRecord)
                    discardedRecords.append(ProjectRegistryDiscardedRecord(
                        identity: Self.recordIdentity(rawRecord, index: index),
                        reason: String(describing: error)
                    ))
                }
            }
            let migrated = Self.coalescedCanonicalRecords(records)
            let rawIDs = (rawRecords as? [[String: Any]])?
                .compactMap { $0["id"] as? String } ?? []
            var quarantineFileURL: URL?
            if !discardedRawRecords.isEmpty {
                do {
                    quarantineFileURL = try quarantine(discardedRawRecords)
                } catch {
                    return ProjectRegistryStoreLoadReport(
                        records: migrated,
                        discardedRecords: discardedRecords,
                        quarantineFileURL: nil,
                        repairFailure: Self.storeError(error)
                    )
                }
            }
            defer {
                if let quarantineFileURL {
                    pruneQuarantineFiles(keeping: quarantineFileURL)
                }
            }
            var repairFailure: ProjectRegistryStoreError?
            if !discardedRecords.isEmpty
                || migrated.count != records.count
                || rawIDs != records.map(\.id.rawValue) {
                do {
                    try save(migrated)
                } catch {
                    repairFailure = Self.storeError(error)
                }
            }
            return ProjectRegistryStoreLoadReport(
                records: migrated,
                discardedRecords: discardedRecords,
                quarantineFileURL: quarantineFileURL,
                repairFailure: repairFailure
            )
        } catch {
            throw Self.storeError(error)
        }
    }

    private static func storeError(_ error: any Error) -> ProjectRegistryStoreError {
        (error as? ProjectRegistryStoreError)
            ?? .persistenceFailed(error.localizedDescription)
    }

    func save(_ records: [ProjectRecord]) throws {
        do {
            guard Set(records.map(\.id)).count == records.count else {
                throw ProjectRegistryStoreError.invalidRecord("Duplicate project IDs")
            }
            try validateRoot(createIfMissing: true)
            if fileManager.fileExists(atPath: fileURL.path) {
                try rejectSymbolicLink(at: fileURL)
            }
            try atomicWrite(Self.encoder.encode(records), fileURL)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: fileURL.path
            )
        } catch let error as ProjectRegistryStoreError {
            throw error
        } catch {
            throw ProjectRegistryStoreError.persistenceFailed(error.localizedDescription)
        }
    }

    private func validateRoot(createIfMissing: Bool) throws {
        let root = fileURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            try rejectSymbolicLink(at: root)
            guard isDirectory.boolValue else {
                throw ProjectRegistryStoreError.invalidRoot(root.path)
            }
        } else if createIfMissing {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        } else {
            throw ProjectRegistryStoreError.invalidRoot(root.path)
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: root.path
            )
        } catch where !createIfMissing {
            Self.logger.error(
                "Unable to harden the project registry directory while reading: \(String(describing: error), privacy: .private)"
            )
        }
    }

    private func rejectSymbolicLink(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw ProjectRegistryStoreError.symbolicLinkRejected(url.path)
        }
    }

    private func quarantine(_ rawRecords: [Any]) throws -> URL {
        let quarantineURL = makeQuarantineURL()
        let data = try JSONSerialization.data(
            withJSONObject: rawRecords,
            options: [.prettyPrinted, .sortedKeys]
        )
        try atomicWrite(data, quarantineURL)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: quarantineURL.path
        )
        return quarantineURL
    }

    private func recoverCorruptDocument(
        _ data: Data,
        reason: String
    ) throws -> ProjectRegistryStoreLoadReport {
        let quarantineURL = makeQuarantineURL()
        try atomicWrite(data, quarantineURL)
        do {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: quarantineURL.path
            )
            try fileManager.removeItem(at: fileURL)
        } catch {
            try? fileManager.removeItem(at: quarantineURL)
            throw error
        }
        pruneQuarantineFiles(keeping: quarantineURL)
        return ProjectRegistryStoreLoadReport(
            records: [],
            discardedRecords: [ProjectRegistryDiscardedRecord(
                identity: "registry",
                reason: reason
            )],
            quarantineFileURL: quarantineURL,
            recoveredWholeDocument: true
        )
    }

    private func makeQuarantineURL() -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(
            "registry-quarantine-\(UUID().uuidString.lowercased()).json",
            isDirectory: false
        )
    }

    private func pruneQuarantineFiles(keeping newestURL: URL) {
        let root = fileURL.deletingLastPathComponent()
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
        } catch {
            Self.logger.error(
                "Unable to enumerate project registry quarantine files: \(String(describing: error), privacy: .private)"
            )
            return
        }
        let candidates = contents.filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("registry-quarantine-"), name.hasSuffix(".json") else {
                return false
            }
            return (try? url.resourceValues(forKeys: keys).isRegularFile) == true
        }
        let older = candidates.filter { $0.standardizedFileURL != newestURL.standardizedFileURL }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: keys).contentModificationDate)
                    ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: keys).contentModificationDate)
                    ?? .distantPast
                if left != right { return left > right }
                return lhs.lastPathComponent > rhs.lastPathComponent
            }
        for staleURL in older.dropFirst(Self.maximumQuarantineFiles - 1) {
            do {
                try fileManager.removeItem(at: staleURL)
            } catch {
                Self.logger.error(
                    "Unable to prune project registry quarantine file at \(staleURL.path, privacy: .private): \(String(describing: error), privacy: .private)"
                )
            }
        }
    }

    private static func recordIdentity(_ rawRecord: Any, index: Int) -> String {
        guard let object = rawRecord as? [String: Any],
              let identity = object["id"] as? String,
              !identity.isEmpty else {
            return "record-\(index + 1)"
        }
        return identity
    }

    private static func coalescedCanonicalRecords(
        _ records: [ProjectRecord]
    ) -> [ProjectRecord] {
        var recordsByID: [ProjectID: ProjectRecord] = [:]
        for record in records {
            guard var existing = recordsByID[record.id] else {
                recordsByID[record.id] = record
                continue
            }
            let newest = existing.lastOpenedAt >= record.lastOpenedAt ? existing : record
            let older = existing.lastOpenedAt >= record.lastOpenedAt ? record : existing
            existing = newest
            existing.lastOpenedAt = max(newest.lastOpenedAt, older.lastOpenedAt)
            existing.openCount = max(newest.openCount, older.openCount)
            existing.isPinned = newest.isPinned || older.isPinned
            existing.isCollapsed = newest.isCollapsed || older.isCollapsed
            existing.accent = newest.accent ?? older.accent
            existing.remoteOrigin = newest.remoteOrigin ?? older.remoteOrigin
            existing.tags = Array(Set(newest.tags + older.tags)).sorted()
            existing.defaultBaseRef = newest.defaultBaseRef ?? older.defaultBaseRef
            existing.defaultAgents = newest.defaultAgents.isEmpty
                ? older.defaultAgents
                : newest.defaultAgents
            recordsByID[record.id] = existing
        }
        return recordsByID.values.sorted {
            $0.id.rawValue.localizedStandardCompare($1.id.rawValue) == .orderedAscending
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
