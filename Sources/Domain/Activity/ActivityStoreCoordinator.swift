// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityStoreCoordinator.swift - App-scoped ownership of the local activity database.

import Foundation

final class ActivityStoreCoordinator: ActivityStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var configuredDatabasePath: String
    private var store: SQLiteActivityStore?

    init(databasePath: String = SQLiteActivityStore.defaultDatabaseURL().path) {
        configuredDatabasePath = databasePath
    }

    func configure(for config: ActivityConfig) {
        let expandedDirectory = (config.storageDirectory as NSString).expandingTildeInPath
        configure(
            databasePath: URL(fileURLWithPath: expandedDirectory, isDirectory: true)
                .appendingPathComponent("activity.sqlite")
                .path
        )
    }

    func configure(databasePath: String) {
        lock.lock()
        defer { lock.unlock() }
        guard databasePath != configuredDatabasePath else { return }
        configuredDatabasePath = databasePath
        store = nil
    }

    var databasePath: String {
        lock.lock()
        defer { lock.unlock() }
        return configuredDatabasePath
    }

    func recordEvent(_ event: ActivityEvent) throws {
        try resolveStore().recordEvent(event)
    }

    func recordTokenUsage(_ record: TokenUsageRecord) throws {
        try resolveStore().recordTokenUsage(record)
    }

    func events(matching query: ActivityStoreQuery) throws -> [ActivityEvent] {
        try resolveStore().events(matching: query)
    }

    func tokenUsage(matching query: ActivityStoreQuery) throws -> [TokenUsageRecord] {
        try resolveStore().tokenUsage(matching: query)
    }

    func deleteAll() throws {
        try resolveStore().deleteAll()
    }

    private func resolveStore() throws -> SQLiteActivityStore {
        lock.lock()
        defer { lock.unlock() }
        if let store { return store }
        let store = try SQLiteActivityStore(databasePath: configuredDatabasePath)
        self.store = store
        return store
    }
}
