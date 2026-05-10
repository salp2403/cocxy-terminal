// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ChannelMigration.swift - Local config migration helpers for side-by-side app channels.

import Foundation

struct ChannelMigrationResult: Sendable, Equatable {
    let copiedItems: [String]
    let skippedExistingItems: [String]
    let missingSourceItems: [String]
}

struct ChannelMigration {
    static let defaultItemNames = [
        "config.toml",
        "agents.toml",
        "sessions",
        "themes",
        "agent",
        "activity",
        "notes",
    ]

    let fileManager: FileManager
    let itemNames: [String]

    init(
        fileManager: FileManager = .default,
        itemNames: [String] = Self.defaultItemNames
    ) {
        self.fileManager = fileManager
        self.itemNames = itemNames
    }

    func migrateConfiguration(
        from sourceDirectory: URL,
        to destinationDirectory: URL,
        replacingExisting: Bool = false
    ) throws -> ChannelMigrationResult {
        try fileManager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var copied: [String] = []
        var skipped: [String] = []
        var missing: [String] = []

        for itemName in itemNames {
            let source = sourceDirectory.appendingPathComponent(itemName)
            let destination = destinationDirectory.appendingPathComponent(itemName)

            guard fileManager.fileExists(atPath: source.path) else {
                missing.append(itemName)
                continue
            }

            if fileManager.fileExists(atPath: destination.path) {
                guard replacingExisting else {
                    skipped.append(itemName)
                    continue
                }
                try fileManager.removeItem(at: destination)
            }

            try fileManager.copyItem(at: source, to: destination)
            copied.append(itemName)
        }

        return ChannelMigrationResult(
            copiedItems: copied,
            skippedExistingItems: skipped,
            missingSourceItems: missing
        )
    }
}
