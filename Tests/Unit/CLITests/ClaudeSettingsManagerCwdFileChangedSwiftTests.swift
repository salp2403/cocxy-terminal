// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ClaudeSettingsManagerCwdFileChangedSwiftTests.swift
// Phase 5 coverage: ClaudeSettingsManager registers the new CwdChanged
// and FileChanged hook events, idempotently installs/uninstalls them, and
// stays in lockstep with the array embedded in AppDelegate+FirstLaunchSetup.

import Foundation
import Testing
import CocxyShared
@testable import CocxyCLILib

@Suite("ClaudeSettingsManager — CwdChanged and FileChanged hook registration")
struct ClaudeSettingsManagerCwdFileChangedSwiftTests {

    private func makeManager() -> (manager: ClaudeSettingsManager, path: String) {
        let directory = NSTemporaryDirectory()
            .appending("cocxy-hooks-cwdfile-\(UUID().uuidString.prefix(8))/")
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        let settingsPath = directory + "settings.json"
        return (ClaudeSettingsManager(settingsFilePath: settingsPath), settingsPath)
    }

    @Test("hookedEventTypes includes both CwdChanged and FileChanged")
    func hookedEventTypesIncludesNewEvents() {
        let events = Set(ClaudeSettingsManager.hookedEventTypes)
        #expect(events.contains("CwdChanged"))
        #expect(events.contains("FileChanged"))
        #expect(events.count == 14)
    }

    @Test("installHooks adds a CwdChanged entry")
    func installHooksAddsCwdChangedEntry() throws {
        let (manager, path) = makeManager()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let result = try manager.installHooks()

        #expect(result.installed)
        #expect(result.hookEvents.contains("CwdChanged"))

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        #expect(hooks["CwdChanged"] != nil)
    }

    @Test("installHooks adds a FileChanged entry")
    func installHooksAddsFileChangedEntry() throws {
        let (manager, path) = makeManager()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let result = try manager.installHooks()

        #expect(result.installed)
        #expect(result.hookEvents.contains("FileChanged"))

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        let entries = try #require(hooks["FileChanged"] as? [[String: Any]])
        let matcher = try #require(entries.first?["matcher"] as? String)
        #expect(matcher == ClaudeFileChangedMatcher.value)
        #expect(!matcher.isEmpty)
        #expect(!ClaudeFileChangedMatcher.watchedRootFiles.contains("."))

        let cwd = URL(fileURLWithPath: "/tmp/cocxy-file-watcher", isDirectory: true)
        let watchedPaths = ClaudeFileChangedMatcher.watchedRootFiles.map {
            cwd.appendingPathComponent($0).standardizedFileURL
        }
        #expect(watchedPaths.allSatisfy {
            $0.deletingLastPathComponent().path == cwd.standardizedFileURL.path
        })
        #expect(watchedPaths.allSatisfy { $0.path != cwd.standardizedFileURL.path })
    }

    @Test("installHooks rewrites an existing Cocxy FileChanged entry with an empty matcher")
    func installHooksRepairsEmptyFileChangedMatcher() throws {
        let (manager, path) = makeManager()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let seed: [String: Any] = [
            "hooks": [
                "FileChanged": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": ClaudeSettingsManager.claudeHookCommand,
                    ]],
                ]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: seed)
            .write(to: URL(fileURLWithPath: path))

        let result = try manager.installHooks()

        #expect(result.installed)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let entries = try #require(hooks["FileChanged"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries.first?["matcher"] as? String == ClaudeFileChangedMatcher.value)
    }

    @Test("installHooks replaces the unsafe recursive FileChanged matcher")
    func installHooksRepairsRecursiveFileChangedMatcher() throws {
        let (manager, path) = makeManager()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let seed: [String: Any] = [
            "hooks": [
                "FileChanged": [[
                    "matcher": ".",
                    "hooks": [[
                        "type": "command",
                        "command": ClaudeSettingsManager.claudeHookCommand,
                    ]],
                ]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: seed)
            .write(to: URL(fileURLWithPath: path))

        let result = try manager.installHooks()

        #expect(result.installed)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let entries = try #require(hooks["FileChanged"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries.first?["matcher"] as? String == ClaudeFileChangedMatcher.value)
    }

    @Test("installHooks is idempotent for CwdChanged")
    func installHooksIsIdempotentForCwdChanged() throws {
        let (manager, path) = makeManager()
        defer { try? FileManager.default.removeItem(atPath: path) }

        _ = try manager.installHooks()
        let secondRun = try manager.installHooks()

        #expect(secondRun.installed == false)
        #expect(secondRun.alreadyInstalled)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        let cwdEntries = hooks["CwdChanged"] as! [[String: Any]]
        // Exactly one entry, not duplicated.
        #expect(cwdEntries.count == 1)
    }

    @Test("uninstallHooks removes the CwdChanged entry")
    func uninstallHooksRemovesCwdChangedEntry() throws {
        let (manager, path) = makeManager()
        defer { try? FileManager.default.removeItem(atPath: path) }

        _ = try manager.installHooks()
        let removal = try manager.uninstallHooks()

        #expect(removal.uninstalled)
        #expect(removal.removedEvents.contains("CwdChanged"))
        #expect(removal.removedEvents.contains("FileChanged"))

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        // The cocxy entries are gone; the per-event keys are removed when
        // the array becomes empty (existing behaviour).
        #expect(hooks["CwdChanged"] == nil)
        #expect(hooks["FileChanged"] == nil)
    }

    @Test("installHooks preserves non-cocxy hook entries on CwdChanged")
    func installHooksPreservesNonCocxyEntries() throws {
        let (manager, path) = makeManager()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Seed a foreign hook for CwdChanged.
        let seed: [String: Any] = [
            "hooks": [
                "CwdChanged": [
                    [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": "/usr/bin/foreign-tool"]
                        ]
                    ]
                ]
            ]
        ]
        let seedData = try JSONSerialization.data(withJSONObject: seed)
        try seedData.write(to: URL(fileURLWithPath: path))

        let result = try manager.installHooks()
        #expect(result.installed)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        let cwdEntries = hooks["CwdChanged"] as! [[String: Any]]
        // Foreign + cocxy entry coexist.
        #expect(cwdEntries.count == 2)
        let commands = cwdEntries.flatMap { entry -> [String] in
            guard let list = entry["hooks"] as? [[String: Any]] else { return [] }
            return list.compactMap { $0["command"] as? String }
        }
        #expect(commands.contains("/usr/bin/foreign-tool"))
        #expect(commands.contains(where: { $0.contains("hook-handler") }))
    }
}
