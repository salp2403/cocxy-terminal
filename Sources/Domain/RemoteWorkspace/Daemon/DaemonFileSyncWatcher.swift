// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonFileSyncWatcher.swift - Monitors remote file changes via daemon.

import Foundation

// MARK: - File Change Event

/// A file system change reported by the remote daemon.
struct FileChangeEvent: Sendable, Equatable {
    enum ChangeType: String, Sendable, Equatable {
        case modified
        case created
        case deleted
    }

    let path: String
    let type: ChangeType
    let timestamp: Date

    /// Parses from a dictionary in the daemon response.
    static func from(dict: [String: Any]) -> FileChangeEvent? {
        guard let path = dict["path"] as? String,
              let typeStr = dict["type"] as? String,
              let type = ChangeType(rawValue: typeStr)
        else { return nil }

        return FileChangeEvent(
            path: path,
            type: type,
            timestamp: Date()
        )
    }
}

// MARK: - Daemon File Sync Watcher

/// Watches remote directories for file changes via the daemon.
///
/// Sends `sync.watch(path)` to start monitoring and periodically
/// polls `sync.changes` to get pending events.
@MainActor
final class DaemonFileSyncWatcher: ObservableObject {

    // MARK: - State

    @Published private(set) var watchedPaths: Set<String> = []
    @Published private(set) var recentChanges: [FileChangeEvent] = []

    // MARK: - Configuration

    /// Maximum number of recent changes to retain.
    let maxRecentChanges: Int

    // MARK: - Dependencies

    private let connection: DaemonConnection
    private var pollTask: Task<Void, Never>?

    init(connection: DaemonConnection, maxRecentChanges: Int = 100) {
        self.connection = connection
        self.maxRecentChanges = maxRecentChanges
    }

    // MARK: - Watch

    /// Starts watching a remote directory for changes.
    ///
    /// - Parameter remotePath: The absolute path on the remote server.
    func watch(remotePath: String) async throws {
        guard connection.isConnected else {
            throw DaemonProtocolError.connectionLost
        }

        let response = try await connection.send(
            cmd: DaemonCommand.syncWatch.rawValue,
            args: ["path": remotePath]
        )

        guard response.ok else {
            throw DaemonProtocolError.invalidResponse
        }

        watchedPaths.insert(remotePath)
        startPollingIfNeeded()
    }

    /// Stops watching a remote directory.
    func unwatch(remotePath: String) {
        watchedPaths.remove(remotePath)
        if watchedPaths.isEmpty {
            stopPolling()
        }
    }

    /// Stops watching all directories.
    func unwatchAll() {
        watchedPaths.removeAll()
        stopPolling()
    }

    // MARK: - Polling

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                guard let self, self.connection.isConnected else { return }
                await self.pollChanges()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollChanges() async {
        guard let response = try? await connection.send(
            cmd: DaemonCommand.syncChanges.rawValue
        ) else { return }

        guard response.ok, let data = response.data,
              let changes = data["changes"] as? [[String: Any]]
        else { return }

        let events = changes.compactMap { FileChangeEvent.from(dict: $0) }
        guard !events.isEmpty else { return }

        recentChanges.append(contentsOf: events)
        if recentChanges.count > maxRecentChanges {
            recentChanges = Array(recentChanges.suffix(maxRecentChanges))
        }
    }
}
