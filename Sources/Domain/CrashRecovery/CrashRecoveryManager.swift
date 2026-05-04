// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CrashRecoveryManager.swift - Local-only crash recovery snapshots and launch state.

import Foundation

struct CrashRecoverySnapshot: Sendable {
    let version: Int
    let savedAt: Date
    let session: Session
    let url: URL?

    init(
        version: Int = 1,
        savedAt: Date,
        session: Session,
        url: URL? = nil
    ) {
        self.version = version
        self.savedAt = savedAt
        self.session = session
        self.url = url
    }
}

struct CrashRecoveryLaunchResult: Sendable {
    let suspectedCrash: Bool
    let latestSnapshot: CrashRecoverySnapshot?
    let crashLogURL: URL?
}

struct CrashRecoveryManager: @unchecked Sendable {
    static let defaultSnapshotDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/Cocxy/snapshots", isDirectory: true)
    static let defaultStateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/Cocxy/crash-recovery-state.json", isDirectory: false)
    static let defaultCrashLogDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Cocxy/crashes", isDirectory: true)

    private let snapshotDirectory: URL
    private let stateURL: URL
    private let crashLogDirectory: URL
    private let now: @Sendable () -> Date
    private let fileManager: FileManager

    init(
        snapshotDirectory: URL = Self.defaultSnapshotDirectory,
        stateURL: URL = Self.defaultStateURL,
        crashLogDirectory: URL = Self.defaultCrashLogDirectory,
        now: @escaping @Sendable () -> Date = { Date() },
        fileManager: FileManager = .default
    ) {
        self.snapshotDirectory = snapshotDirectory.standardizedFileURL
        self.stateURL = stateURL.standardizedFileURL
        self.crashLogDirectory = crashLogDirectory.standardizedFileURL
        self.now = now
        self.fileManager = fileManager
    }

    @discardableResult
    func beginLaunch() throws -> CrashRecoveryLaunchResult {
        let previousState = try readState()
        let suspectedCrash = previousState.map { $0.cleanShutdownAt == nil } ?? false
        let latestSnapshot = suspectedCrash ? try loadLatestSnapshot() : nil
        let crashLogURL = suspectedCrash
            ? try writeCrashLog(previousState: previousState, latestSnapshot: latestSnapshot)
            : nil

        try writeState(LaunchState(
            launchID: UUID(),
            startedAt: now(),
            cleanShutdownAt: nil
        ))

        return CrashRecoveryLaunchResult(
            suspectedCrash: suspectedCrash,
            latestSnapshot: latestSnapshot,
            crashLogURL: crashLogURL
        )
    }

    func markCleanShutdown() throws {
        let existing = try readState()
        try writeState(LaunchState(
            launchID: existing?.launchID ?? UUID(),
            startedAt: existing?.startedAt ?? now(),
            cleanShutdownAt: now()
        ))
    }

    @discardableResult
    func saveSnapshot(_ session: Session) throws -> CrashRecoverySnapshot {
        try createSecureDirectory(snapshotDirectory)
        let savedAt = now()
        let snapshot = CrashRecoverySnapshot(savedAt: savedAt, session: session)
        let url = snapshotDirectory.appendingPathComponent(
            "\(Self.snapshotName(for: savedAt))-\(UUID().uuidString).json",
            isDirectory: false
        )

        let payload = SnapshotPayload(snapshot: snapshot)
        try encoded(payload).write(to: url, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return CrashRecoverySnapshot(
            version: snapshot.version,
            savedAt: snapshot.savedAt,
            session: snapshot.session,
            url: url
        )
    }

    func loadLatestSnapshot() throws -> CrashRecoverySnapshot? {
        guard fileManager.fileExists(atPath: snapshotDirectory.path) else { return nil }
        let urls = try fileManager.contentsOfDirectory(
            at: snapshotDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let snapshots = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> CrashRecoverySnapshot? in
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else {
                    return nil
                }
                guard let payload = try? decoded(SnapshotPayload.self, from: url) else {
                    return nil
                }
                return CrashRecoverySnapshot(
                    version: payload.version,
                    savedAt: payload.savedAt,
                    session: payload.session,
                    url: url
                )
            }

        return snapshots.sorted { $0.savedAt > $1.savedAt }.first
    }

    @discardableResult
    func pruneSnapshots(keepNewest count: Int) throws -> Int {
        guard fileManager.fileExists(atPath: snapshotDirectory.path) else { return 0 }
        let urls = try fileManager.contentsOfDirectory(
            at: snapshotDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let snapshots = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> CrashRecoverySnapshot? in
                guard let payload = try? decoded(SnapshotPayload.self, from: url) else {
                    return nil
                }
                return CrashRecoverySnapshot(
                    version: payload.version,
                    savedAt: payload.savedAt,
                    session: payload.session,
                    url: url
                )
            }
            .sorted { $0.savedAt > $1.savedAt }

        var deleted = 0
        for snapshot in snapshots.dropFirst(max(0, count)) {
            if let url = snapshot.url {
                try fileManager.removeItem(at: url)
                deleted += 1
            }
        }
        return deleted
    }

    private struct LaunchState: Codable {
        let launchID: UUID
        let startedAt: Date
        let cleanShutdownAt: Date?
    }

    private struct SnapshotPayload: Codable {
        let version: Int
        let savedAt: Date
        let session: Session

        init(snapshot: CrashRecoverySnapshot) {
            version = snapshot.version
            savedAt = snapshot.savedAt
            session = snapshot.session
        }
    }

    private struct CrashLogPayload: Codable {
        let version: Int
        let detectedAt: Date
        let reason: String
        let previousLaunchID: UUID?
        let previousLaunchStartedAt: Date?
        let latestSnapshotFile: String?
    }

    private func readState() throws -> LaunchState? {
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
        do {
            return try decoded(LaunchState.self, from: stateURL)
        } catch is DecodingError {
            return nil
        }
    }

    private func writeState(_ state: LaunchState) throws {
        try createSecureDirectory(stateURL.deletingLastPathComponent())
        try encoded(state).write(to: stateURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    private func writeCrashLog(
        previousState: LaunchState?,
        latestSnapshot: CrashRecoverySnapshot?
    ) throws -> URL {
        try createSecureDirectory(crashLogDirectory)
        let detectedAt = now()
        let url = crashLogDirectory.appendingPathComponent(
            "\(Self.snapshotName(for: detectedAt))-\(UUID().uuidString).json",
            isDirectory: false
        )
        let payload = CrashLogPayload(
            version: 1,
            detectedAt: detectedAt,
            reason: "unclean-shutdown",
            previousLaunchID: previousState?.launchID,
            previousLaunchStartedAt: previousState?.startedAt,
            latestSnapshotFile: latestSnapshot?.url?.lastPathComponent
        )
        try encoded(payload).write(to: url, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private func createSecureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func decoded<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private static func snapshotName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }
}
