// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Update channel migration")
struct ChannelMigrationSwiftTestingTests {

    @Test("disk config provider separates stable preview and nightly config files")
    func diskConfigProviderSeparatesChannelConfigFiles() {
        let home = "/Users/example"

        #expect(
            DiskConfigFileProvider.configFilePath(homeDirectory: home, channel: .stable)
                == "/Users/example/.config/cocxy/config.toml"
        )
        #expect(
            DiskConfigFileProvider.configFilePath(homeDirectory: home, channel: .preview)
                == "/Users/example/.config/cocxy/dev.cocxy.terminal.preview/config.toml"
        )
        #expect(
            DiskConfigFileProvider.configFilePath(homeDirectory: home, channel: .nightly)
                == "/Users/example/.config/cocxy/dev.cocxy.terminal.nightly/config.toml"
        )
    }

    @Test("migration copies channel safe user config items without sockets")
    func migrationCopiesChannelSafeUserConfigItemsWithoutSockets() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("stable", isDirectory: true)
        let destination = root.appendingPathComponent("preview", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "channel = \"stable\"\n".write(
            to: source.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try "agents = []\n".write(
            to: source.appendingPathComponent("agents.toml"),
            atomically: true,
            encoding: .utf8
        )
        try "socket".write(
            to: source.appendingPathComponent("cocxy.sock"),
            atomically: true,
            encoding: .utf8
        )

        let result = try ChannelMigration(itemNames: ["config.toml", "agents.toml"])
            .migrateConfiguration(
            from: source,
            to: destination
        )

        #expect(result.copiedItems == ["config.toml", "agents.toml"])
        #expect(
            ChannelMigration.defaultItemNames.contains("cocxy.sock") == false,
            "The production migration allowlist must never copy live socket files."
        )
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("config.toml").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("agents.toml").path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("cocxy.sock").path))
    }

    @Test("migration preserves existing destination files unless replacement is explicit")
    func migrationPreservesExistingDestinationFilesUnlessReplacementIsExplicit() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("stable", isDirectory: true)
        let destination = root.appendingPathComponent("nightly", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "source".write(
            to: source.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try "destination".write(
            to: destination.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let skipped = try ChannelMigration(itemNames: ["config.toml"])
            .migrateConfiguration(from: source, to: destination)
        let preserved = try String(
            contentsOf: destination.appendingPathComponent("config.toml"),
            encoding: .utf8
        )

        #expect(skipped.copiedItems.isEmpty)
        #expect(skipped.skippedExistingItems == ["config.toml"])
        #expect(preserved == "destination")

        let replaced = try ChannelMigration(itemNames: ["config.toml"])
            .migrateConfiguration(from: source, to: destination, replacingExisting: true)
        let newContent = try String(
            contentsOf: destination.appendingPathComponent("config.toml"),
            encoding: .utf8
        )

        #expect(replaced.copiedItems == ["config.toml"])
        #expect(newContent == "source")
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-channel-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
