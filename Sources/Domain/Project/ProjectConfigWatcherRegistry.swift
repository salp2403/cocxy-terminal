// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectConfigWatcherRegistry.swift - App-scoped project config watch sharing.

import Darwin
import Foundation

struct ProjectConfigWatchLease: Hashable, Sendable {
    fileprivate let key: ProjectConfigWatchKey
    fileprivate let subscriberID: UUID
}

private struct ProjectConfigWatchKey: Hashable, Sendable {
    let projectID: ProjectID
    let configPath: String
}

@MainActor
final class ProjectConfigWatcherRegistry {
    struct FileSnapshot: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int

        static func read(path: String) -> FileSnapshot? {
            var value = stat()
            guard lstat(path, &value) == 0 else { return nil }
            return FileSnapshot(
                device: UInt64(value.st_dev),
                inode: UInt64(value.st_ino),
                size: value.st_size,
                modifiedSeconds: value.st_mtimespec.tv_sec,
                modifiedNanoseconds: value.st_mtimespec.tv_nsec
            )
        }
    }

    private struct Entry {
        let key: ProjectConfigWatchKey
        var subscribers: [UUID: () -> Void]
        var watcher: (any ProjectConfigWatching)?
        var fallbackSnapshot: FileSnapshot?
        var accessSequence: UInt64
    }

    private let maximumWatcherCount: Int
    private let fallbackPollInterval: TimeInterval
    private let watcherFactory: (String) -> any ProjectConfigWatching
    private let snapshotProvider: (String) -> FileSnapshot?
    private var entries: [ProjectConfigWatchKey: Entry] = [:]
    private var accessSequence: UInt64 = 0
    private var fallbackTimer: DispatchSourceTimer?

    init(
        maximumWatcherCount: Int = 16,
        fallbackPollInterval: TimeInterval = 0.5,
        watcherFactory: @escaping (String) -> any ProjectConfigWatching = {
            ProjectConfigWatcher(configFilePath: $0)
        },
        snapshotProvider: @escaping (String) -> FileSnapshot? = FileSnapshot.read
    ) {
        precondition(maximumWatcherCount > 0)
        precondition(fallbackPollInterval > 0)
        self.maximumWatcherCount = maximumWatcherCount
        self.fallbackPollInterval = fallbackPollInterval
        self.watcherFactory = watcherFactory
        self.snapshotProvider = snapshotProvider
    }

    @discardableResult
    func acquire(
        projectID: ProjectID,
        configFilePath: String,
        onChange: @escaping () -> Void
    ) -> ProjectConfigWatchLease {
        let key = ProjectConfigWatchKey(
            projectID: projectID,
            configPath: URL(fileURLWithPath: configFilePath).standardizedFileURL.path
        )
        let subscriberID = UUID()
        accessSequence &+= 1

        if var entry = entries[key] {
            entry.subscribers[subscriberID] = onChange
            entry.accessSequence = accessSequence
            entries[key] = entry
        } else {
            entries[key] = Entry(
                key: key,
                subscribers: [subscriberID: onChange],
                watcher: nil,
                fallbackSnapshot: snapshotProvider(key.configPath),
                accessSequence: accessSequence
            )
        }

        promoteToFileWatcher(key)
        updateFallbackTimer()
        return ProjectConfigWatchLease(key: key, subscriberID: subscriberID)
    }

    func release(_ lease: ProjectConfigWatchLease) {
        guard var entry = entries[lease.key],
              entry.subscribers.removeValue(forKey: lease.subscriberID) != nil else {
            return
        }

        if entry.subscribers.isEmpty {
            entry.watcher?.stopWatching()
            entries.removeValue(forKey: lease.key)
            promoteMostRecentFallbackIfPossible()
        } else {
            entries[lease.key] = entry
        }
        updateFallbackTimer()
    }

    func touch(_ lease: ProjectConfigWatchLease) {
        guard var entry = entries[lease.key],
              entry.subscribers[lease.subscriberID] != nil else {
            return
        }
        accessSequence &+= 1
        entry.accessSequence = accessSequence
        entries[lease.key] = entry
        promoteToFileWatcher(lease.key)
        updateFallbackTimer()
    }

    func matches(
        _ lease: ProjectConfigWatchLease,
        projectID: ProjectID,
        configFilePath: String
    ) -> Bool {
        lease.key == ProjectConfigWatchKey(
            projectID: projectID,
            configPath: URL(fileURLWithPath: configFilePath).standardizedFileURL.path
        )
    }

    func removeAll() {
        for entry in entries.values {
            entry.watcher?.stopWatching()
        }
        entries.removeAll()
        fallbackTimer?.cancel()
        fallbackTimer = nil
    }

    var activeWatcherCount: Int {
        entries.values.lazy.filter { $0.watcher != nil }.count
    }

    var fallbackEntryCount: Int {
        entries.values.lazy.filter { $0.watcher == nil }.count
    }

    func referenceCount(projectID: ProjectID, configFilePath: String) -> Int {
        let key = ProjectConfigWatchKey(
            projectID: projectID,
            configPath: URL(fileURLWithPath: configFilePath).standardizedFileURL.path
        )
        return entries[key]?.subscribers.count ?? 0
    }

    func isUsingFileWatcher(projectID: ProjectID, configFilePath: String) -> Bool {
        let key = ProjectConfigWatchKey(
            projectID: projectID,
            configPath: URL(fileURLWithPath: configFilePath).standardizedFileURL.path
        )
        return entries[key]?.watcher != nil
    }

    func pollFallbackEntriesForTesting() {
        pollFallbackEntries()
    }

    private func promoteToFileWatcher(_ key: ProjectConfigWatchKey) {
        guard entries[key]?.watcher == nil else { return }

        if activeWatcherCount >= maximumWatcherCount,
           let demotionKey = entries.values
            .filter({ $0.watcher != nil && $0.key != key })
            .min(by: { $0.accessSequence < $1.accessSequence })?
            .key {
            demoteToFallback(demotionKey)
        }

        guard activeWatcherCount < maximumWatcherCount,
              var entry = entries[key] else {
            return
        }

        let watcher = watcherFactory(key.configPath)
        entry.watcher = watcher
        entry.fallbackSnapshot = snapshotProvider(key.configPath)
        entries[key] = entry
        watcher.startWatching { [weak self] in
            self?.handleFileSystemChange(for: key)
        }

        if !watcher.isWatching {
            demoteToFallback(key)
        }
    }

    private func demoteToFallback(_ key: ProjectConfigWatchKey) {
        guard var entry = entries[key] else { return }
        entry.watcher?.stopWatching()
        entry.watcher = nil
        entry.fallbackSnapshot = snapshotProvider(key.configPath)
        entries[key] = entry
    }

    private func promoteMostRecentFallbackIfPossible() {
        guard activeWatcherCount < maximumWatcherCount,
              let key = entries.values
                .filter({ $0.watcher == nil })
                .max(by: { $0.accessSequence < $1.accessSequence })?
                .key else {
            return
        }
        promoteToFileWatcher(key)
    }

    private func handleFileSystemChange(for key: ProjectConfigWatchKey) {
        guard var entry = entries[key] else { return }
        let callbacks = Array(entry.subscribers.values)
        if entry.watcher?.isWatching == false {
            entry.watcher = nil
            entry.fallbackSnapshot = snapshotProvider(key.configPath)
            entries[key] = entry
            updateFallbackTimer()
        }
        callbacks.forEach { $0() }
    }

    private func updateFallbackTimer() {
        let needsTimer = entries.values.contains { $0.watcher == nil }
        guard needsTimer else {
            fallbackTimer?.cancel()
            fallbackTimer = nil
            return
        }
        guard fallbackTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + fallbackPollInterval,
            repeating: fallbackPollInterval
        )
        timer.setEventHandler { [weak self] in
            self?.pollFallbackEntries()
        }
        timer.resume()
        fallbackTimer = timer
    }

    private func pollFallbackEntries() {
        let fallbackKeys = entries.values
            .filter { $0.watcher == nil }
            .map(\.key)

        for key in fallbackKeys {
            guard var entry = entries[key] else { continue }
            let snapshot = snapshotProvider(key.configPath)
            guard snapshot != entry.fallbackSnapshot else { continue }
            entry.fallbackSnapshot = snapshot
            entries[key] = entry
            Array(entry.subscribers.values).forEach { $0() }
        }
    }
}
