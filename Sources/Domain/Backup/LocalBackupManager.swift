// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LocalBackupManager.swift - Local-only backup creation, restore, and pruning.

import Foundation

enum LocalBackupError: Error, Sendable, Equatable {
    case disabled
    case missingBackupArtifact(BackupArtifactKind)
}

struct LocalBackupManager: @unchecked Sendable {
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    init(
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.now = now
    }

    func createBackup(
        config: BackupConfig,
        roots: BackupArtifactRoots = .defaults()
    ) throws -> BackupCreateResult {
        guard config.enabled else { throw LocalBackupError.disabled }

        let createdAt = now()
        let backupRoot = Self.expandedURL(config.storageDirectory)
        let backupURL = backupRoot.appendingPathComponent(Self.backupDirectoryName(for: createdAt), isDirectory: true)
        try fileManager.createDirectory(
            at: backupURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var entries: [BackupManifestEntry] = []
        for kind in config.artifactKinds {
            let source = roots.sourceURL(for: kind)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = backupURL.appendingPathComponent(kind.backupFolderName, isDirectory: true)
            let fileCount = try copyArtifact(kind: kind, from: source, to: destination)
            if fileCount > 0 {
                entries.append(BackupManifestEntry(
                    kind: kind,
                    path: kind.backupFolderName,
                    fileCount: fileCount
                ))
            }
        }

        let manifest = BackupManifest(
            createdAt: createdAt,
            artifacts: entries.sorted { $0.kind < $1.kind }
        )
        try writeManifest(manifest, to: backupURL.appendingPathComponent("manifest.json"))
        return BackupCreateResult(backupURL: backupURL, manifest: manifest)
    }

    func restore(
        kind: BackupArtifactKind,
        from backupURL: URL,
        to roots: BackupArtifactRoots = .defaults()
    ) throws -> BackupRestoreResult {
        let manifest = try readManifest(from: backupURL.appendingPathComponent("manifest.json"))
        guard let entry = manifest.artifacts.first(where: { $0.kind == kind }) else {
            throw LocalBackupError.missingBackupArtifact(kind)
        }

        let source = try Self.containedBackupArtifactURL(entry.path, under: backupURL)
        let destination = roots.sourceURL(for: kind)
        let restored: Int
        if restoresAsSingleFile(kind) {
            let file = source.appendingPathComponent(destination.lastPathComponent, isDirectory: false)
            restored = try copyFileReplacingExisting(from: file, to: destination)
        } else {
            restored = try restoreDirectoryContentsExactly(from: source, to: destination, kind: kind)
        }
        return BackupRestoreResult(kind: kind, restoredFiles: restored)
    }

    func availableBackups(storageDirectory: String) throws -> [BackupSnapshotSummary] {
        let backupRoot = Self.expandedURL(storageDirectory)
        guard fileManager.fileExists(atPath: backupRoot.path) else {
            return []
        }

        return try backupDirectories(in: backupRoot)
            .compactMap { directory in
                let manifestURL = directory.url.appendingPathComponent("manifest.json", isDirectory: false)
                guard let manifest = try? readManifest(from: manifestURL) else {
                    return nil
                }
                return BackupSnapshotSummary(backupURL: directory.url, manifest: manifest)
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.backupURL.lastPathComponent > rhs.backupURL.lastPathComponent
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func pruneBackups(config: BackupConfig) throws -> BackupPruneResult {
        let backupRoot = Self.expandedURL(config.storageDirectory)
        guard fileManager.fileExists(atPath: backupRoot.path) else {
            return BackupPruneResult(deletedCount: 0)
        }

        let backups = try backupDirectories(in: backupRoot)
        let keep = Set(backupsToKeep(
            from: backups,
            dailyRetentionCount: config.dailyRetentionCount,
            monthlyRetentionCount: config.monthlyRetentionCount
        ).map(\.url))

        var deleted = 0
        for backup in backups where !keep.contains(backup.url) {
            try fileManager.removeItem(at: backup.url)
            deleted += 1
        }
        return BackupPruneResult(deletedCount: deleted)
    }

    private func copyArtifact(
        kind: BackupArtifactKind,
        from source: URL,
        to destination: URL
    ) throws -> Int {
        switch try sourceArtifactType(for: source) {
        case .file:
            return try copyFileReplacingExisting(
                from: source,
                to: destination.appendingPathComponent(source.lastPathComponent, isDirectory: false)
            )
        case .directory:
            return try copyDirectoryContentsReplacingExisting(from: source, to: destination)
        case nil:
            return 0
        }
    }

    private func copyDirectoryContentsReplacingExisting(from source: URL, to destination: URL) throws -> Int {
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }

        var copied = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let relativePath = try Self.relativePath(for: url, under: source)
            let target = destination.appendingPathComponent(relativePath, isDirectory: values.isDirectory == true)
            if values.isDirectory == true {
                try fileManager.createDirectory(
                    at: target,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } else if values.isRegularFile == true {
                copied += try copyFileReplacingExisting(from: url, to: target)
            }
        }
        return copied
    }

    private func restoreDirectoryContentsExactly(
        from source: URL,
        to destination: URL,
        kind: BackupArtifactKind
    ) throws -> Int {
        guard fileManager.fileExists(atPath: source.path),
              try sourceArtifactType(for: source) == .directory else {
            throw LocalBackupError.missingBackupArtifact(kind)
        }

        try validateRestoreDestination(destination)
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let stagingDirectory = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).restore-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            let copied = try copyDirectoryContentsReplacingExisting(from: source, to: stagingDirectory)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: stagingDirectory, to: destination)
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path)
            return copied
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    private func validateRestoreDestination(_ destination: URL) throws {
        let standardized = destination.standardizedFileURL
        let path = standardized.path
        let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard path != "/",
              path != homePath,
              standardized.pathComponents.count > 2 else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
    }

    private func copyFileReplacingExisting(from source: URL, to destination: URL) throws -> Int {
        guard fileManager.fileExists(atPath: source.path) else { return 0 }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return 1
    }

    private enum SourceArtifactType {
        case directory
        case file
    }

    private func sourceArtifactType(for source: URL) throws -> SourceArtifactType? {
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { return nil }
        if values.isDirectory == true { return .directory }
        if values.isRegularFile == true { return .file }
        return nil
    }

    private func restoresAsSingleFile(_ kind: BackupArtifactKind) -> Bool {
        switch kind {
        case .settings, .macros, .encryptedSSHHosts:
            return true
        case .notebooks, .workflows, .skills, .notes, .themes, .aiConversations:
            return false
        }
    }

    private func writeManifest(_ manifest: BackupManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func readManifest(from url: URL) throws -> BackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupManifest.self, from: Data(contentsOf: url))
    }

    private struct BackupDirectory: Hashable {
        let url: URL
        let date: Date
    }

    private func backupDirectories(in root: URL) throws -> [BackupDirectory] {
        let urls = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { url in
            guard let date = Self.dateFromBackupDirectoryName(url.lastPathComponent) else { return nil }
            return BackupDirectory(url: url, date: date)
        }
    }

    private func backupsToKeep(
        from backups: [BackupDirectory],
        dailyRetentionCount: Int,
        monthlyRetentionCount: Int
    ) -> [BackupDirectory] {
        let sortedDescending = backups.sorted { $0.date > $1.date }
        let daily = Array(sortedDescending.prefix(max(1, dailyRetentionCount)))
        let dailySet = Set(daily)
        let older = sortedDescending.filter { !dailySet.contains($0) }

        var monthlyByMonth: [String: BackupDirectory] = [:]
        for backup in older {
            let key = Self.monthKey(for: backup.date)
            if let existing = monthlyByMonth[key] {
                if backup.date < existing.date {
                    monthlyByMonth[key] = backup
                }
            } else {
                monthlyByMonth[key] = backup
            }
        }
        let monthly = monthlyByMonth.values
            .sorted { $0.date > $1.date }
            .prefix(max(0, monthlyRetentionCount))

        return Array(Set(daily).union(monthly))
    }

    private static func expandedURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
    }

    private static func backupDirectoryName(for date: Date) -> String {
        makeBackupNameFormatter().string(from: date)
    }

    private static func dateFromBackupDirectoryName(_ value: String) -> Date? {
        makeBackupNameFormatter().date(from: value)
    }

    private static func monthKey(for date: Date) -> String {
        makeMonthFormatter().string(from: date)
    }

    private static func makeBackupNameFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }

    private static func makeMonthFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }

    private static func relativePath(for url: URL, under root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func containedBackupArtifactURL(_ relativePath: String, under backupURL: URL) throws -> URL {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw CocoaError(.fileReadInvalidFileName)
        }

        let root = backupURL.standardizedFileURL
        let artifact = root.appendingPathComponent(trimmedPath, isDirectory: true).standardizedFileURL
        guard artifact.path.hasPrefix(root.path + "/") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return artifact
    }
}
