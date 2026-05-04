// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AutomaticBackupController.swift - Daily local backup launch gate.

import Foundation

enum AutomaticBackupSkipReason: String, Codable, Sendable, Equatable {
    case disabled
    case alreadyRanToday
}

struct AutomaticBackupRunResult: Sendable, Equatable {
    let createdBackupURL: URL?
    let reason: AutomaticBackupSkipReason?
    let prunedCount: Int
}

struct AutomaticBackupController: @unchecked Sendable {
    private let roots: BackupArtifactRoots
    private let stateURL: URL
    private let manager: LocalBackupManager
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let fileManager: FileManager

    init(
        roots: BackupArtifactRoots = .defaults(),
        stateURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cocxy/backup-state.json", isDirectory: false),
        manager: LocalBackupManager? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            return calendar
        }(),
        fileManager: FileManager = .default
    ) {
        self.roots = roots
        self.stateURL = stateURL
        self.manager = manager ?? LocalBackupManager(fileManager: fileManager, now: now)
        self.now = now
        self.calendar = calendar
        self.fileManager = fileManager
    }

    func runIfDue(config: BackupConfig) throws -> AutomaticBackupRunResult {
        guard config.enabled else {
            return AutomaticBackupRunResult(createdBackupURL: nil, reason: .disabled, prunedCount: 0)
        }

        let currentDate = now()
        if let state = try readState(),
           calendar.isDate(state.lastBackupAt, inSameDayAs: currentDate) {
            return AutomaticBackupRunResult(createdBackupURL: nil, reason: .alreadyRanToday, prunedCount: 0)
        }

        let backup = try manager.createBackup(config: config, roots: roots)
        let prune = try manager.pruneBackups(config: config)
        try writeState(AutomaticBackupState(lastBackupAt: currentDate))
        return AutomaticBackupRunResult(
            createdBackupURL: backup.backupURL,
            reason: nil,
            prunedCount: prune.deletedCount
        )
    }

    private struct AutomaticBackupState: Codable {
        let lastBackupAt: Date
    }

    private func readState() throws -> AutomaticBackupState? {
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AutomaticBackupState.self, from: Data(contentsOf: stateURL))
    }

    private func writeState(_ state: AutomaticBackupState) throws {
        try fileManager.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: stateURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }
}
