// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HooksCommandTests.swift - Tests for hooks install/uninstall/status and hook-handler CLI commands.

import XCTest
@testable import CocxyCLILib

// MARK: - Claude Settings Manager Tests

/// Tests for `ClaudeSettingsManager`: reads, writes, and merges hooks
/// in `~/.claude/settings.json` without overwriting user hooks.
final class ClaudeSettingsManagerTests: XCTestCase {

    // MARK: - Setup / Teardown

    private var tempDirectory: String!
    private var settingsFilePath: String!

    override func setUp() {
        super.setUp()
        tempDirectory = NSTemporaryDirectory()
            .appending("cocxy-hooks-test-\(UUID().uuidString.prefix(8))/")
        try? FileManager.default.createDirectory(
            atPath: tempDirectory,
            withIntermediateDirectories: true
        )
        settingsFilePath = tempDirectory + "settings.json"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDirectory)
        super.tearDown()
    }

    // MARK: - 1. Install creates correct hook entries

    func testInstallCreatesCorrectHookEntries() throws {
        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)

        let result = try manager.installHooks()

        XCTAssertTrue(result.installed)
        XCTAssertFalse(result.alreadyInstalled)
        XCTAssertEqual(result.hookEvents.count, ClaudeSettingsManager.hookedEventTypes.count)
        XCTAssertTrue(result.hookEvents.contains("Stop"))
        XCTAssertTrue(result.hookEvents.contains("PreToolUse"))
        XCTAssertTrue(result.hookEvents.contains("PostToolUse"))
        XCTAssertTrue(result.hookEvents.contains("SubagentStop"))
        XCTAssertTrue(result.hookEvents.contains("Notification"))
        XCTAssertTrue(result.hookEvents.contains("SessionStart"))
        XCTAssertTrue(result.hookEvents.contains("SessionEnd"))
        XCTAssertTrue(result.hookEvents.contains("TeammateIdle"))
        XCTAssertTrue(result.hookEvents.contains("TaskCompleted"))
        XCTAssertTrue(result.hookEvents.contains("UserPromptSubmit"))
        XCTAssertTrue(result.hookEvents.contains("PostToolUseFailure"))
        XCTAssertTrue(result.hookEvents.contains("SubagentStart"))
        XCTAssertTrue(result.hookEvents.contains("CwdChanged"))
        XCTAssertTrue(result.hookEvents.contains("FileChanged"))

        // Verify file was written
        let data = try Data(contentsOf: URL(fileURLWithPath: settingsFilePath))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        XCTAssertEqual(hooks.count, ClaudeSettingsManager.hookedEventTypes.count)

        // Verify structure of a hook entry
        let stopHooks = hooks["Stop"] as! [[String: Any]]
        XCTAssertEqual(stopHooks.count, 1)
        let firstHook = stopHooks[0]
        XCTAssertEqual(firstHook["matcher"] as? String, "")
        let hookCommands = firstHook["hooks"] as! [[String: Any]]
        XCTAssertEqual(hookCommands.count, 1)
        XCTAssertEqual(hookCommands[0]["type"] as? String, "command")
        XCTAssertEqual(hookCommands[0]["command"] as? String, "cocxy hook-handler")
    }

    // MARK: - 2. Install preserves existing user hooks

    func testInstallPreservesExistingUserHooks() throws {
        // Write existing user hooks
        let existingSettings: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": "my-custom-tool notify"]
                        ]
                    ]
                ],
                "PreToolUse": [
                    [
                        "matcher": "Bash",
                        "hooks": [
                            ["type": "command", "command": "my-security-check"]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existingSettings, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: settingsFilePath))

        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)
        let result = try manager.installHooks()

        XCTAssertTrue(result.installed)

        // Read back and verify user hooks are preserved
        let readData = try Data(contentsOf: URL(fileURLWithPath: settingsFilePath))
        let settings = try JSONSerialization.jsonObject(with: readData) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        // Stop should have both the user hook and the cocxy hook
        let stopHooks = hooks["Stop"] as! [[String: Any]]
        XCTAssertEqual(stopHooks.count, 2)

        // PreToolUse should have both the user hook and the cocxy hook
        let preToolHooks = hooks["PreToolUse"] as! [[String: Any]]
        XCTAssertEqual(preToolHooks.count, 2)

        // Verify user hook is still there
        let userStopHook = stopHooks[0]
        let userCommands = userStopHook["hooks"] as! [[String: Any]]
        XCTAssertEqual(userCommands[0]["command"] as? String, "my-custom-tool notify")
    }

    // MARK: - 3. Install is idempotent (already installed message)

    func testInstallIsIdempotent() throws {
        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)

        // First install
        let firstResult = try manager.installHooks()
        XCTAssertTrue(firstResult.installed)
        XCTAssertFalse(firstResult.alreadyInstalled)

        // Second install -- should detect already installed
        let secondResult = try manager.installHooks()
        XCTAssertFalse(secondResult.installed)
        XCTAssertTrue(secondResult.alreadyInstalled)
    }

    // MARK: - 4. Uninstall removes only cocxy hooks

    func testUninstallRemovesOnlyCocxyHooks() throws {
        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)

        // Install first
        _ = try manager.installHooks()

        // Add a user hook to Stop
        let readData = try Data(contentsOf: URL(fileURLWithPath: settingsFilePath))
        var settings = try JSONSerialization.jsonObject(with: readData) as! [String: Any]
        var hooks = settings["hooks"] as! [String: Any]
        var stopHooks = hooks["Stop"] as! [[String: Any]]
        stopHooks.insert([
            "matcher": "",
            "hooks": [["type": "command", "command": "my-user-hook"]]
        ], at: 0)
        hooks["Stop"] = stopHooks
        settings["hooks"] = hooks
        let updatedData = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
        try updatedData.write(to: URL(fileURLWithPath: settingsFilePath))

        // Uninstall
        let result = try manager.uninstallHooks()

        XCTAssertTrue(result.uninstalled)
        XCTAssertEqual(result.removedEvents.count, ClaudeSettingsManager.hookedEventTypes.count)

        // Verify user hooks remain
        let finalData = try Data(contentsOf: URL(fileURLWithPath: settingsFilePath))
        let finalSettings = try JSONSerialization.jsonObject(with: finalData) as! [String: Any]
        let finalHooks = finalSettings["hooks"] as! [String: Any]

        // Stop should still have the user hook
        let finalStopHooks = finalHooks["Stop"] as! [[String: Any]]
        XCTAssertEqual(finalStopHooks.count, 1)
        let remainingCommands = finalStopHooks[0]["hooks"] as! [[String: Any]]
        XCTAssertEqual(remainingCommands[0]["command"] as? String, "my-user-hook")
    }

    // MARK: - 5. Uninstall preserves user hooks

    func testUninstallPreservesUserHooks() throws {
        // Set up settings with only user hooks
        let userSettings: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "",
                        "hooks": [["type": "command", "command": "my-user-tool"]]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: userSettings, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: settingsFilePath))

        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)
        let result = try manager.uninstallHooks()

        XCTAssertFalse(result.uninstalled)
        XCTAssertTrue(result.nothingToRemove)

        // User hooks are untouched
        let readData = try Data(contentsOf: URL(fileURLWithPath: settingsFilePath))
        let settings = try JSONSerialization.jsonObject(with: readData) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        let stopHooks = hooks["Stop"] as! [[String: Any]]
        XCTAssertEqual(stopHooks.count, 1)
    }

    // MARK: - 6. Uninstall nothing to remove message

    func testUninstallNothingToRemove() throws {
        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)
        let result = try manager.uninstallHooks()

        XCTAssertFalse(result.uninstalled)
        XCTAssertTrue(result.nothingToRemove)
    }

    // MARK: - 7. Status detects installed hooks

    func testStatusDetectsInstalledHooks() throws {
        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)
        _ = try manager.installHooks()

        let status = try manager.hooksStatus()

        XCTAssertTrue(status.installed)
        XCTAssertEqual(status.installedEvents.count, ClaudeSettingsManager.hookedEventTypes.count)
        XCTAssertTrue(status.installedEvents.contains("Stop"))
        XCTAssertTrue(status.installedEvents.contains("PreToolUse"))
        XCTAssertTrue(status.installedEvents.contains("PostToolUse"))
        XCTAssertTrue(status.installedEvents.contains("SubagentStop"))
        XCTAssertTrue(status.installedEvents.contains("Notification"))
        XCTAssertTrue(status.installedEvents.contains("SessionStart"))
        XCTAssertTrue(status.installedEvents.contains("TeammateIdle"))
    }

    // MARK: - 8. Status detects missing hooks

    func testStatusDetectsMissingHooks() throws {
        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)
        let status = try manager.hooksStatus()

        XCTAssertFalse(status.installed)
        XCTAssertTrue(status.installedEvents.isEmpty)
    }

    // MARK: - 9. Settings JSON parsing: valid file

    func testParsingValidSettingsFile() throws {
        let validSettings: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["matcher": "", "hooks": [["type": "command", "command": "test"]]]
                ]
            ],
            "permissions": ["allow": ["/tmp"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: validSettings, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: settingsFilePath))

        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)
        let status = try manager.hooksStatus()

        // Should parse without error
        XCTAssertFalse(status.installed) // No cocxy hooks, just user hooks
    }

    // MARK: - 10. Settings JSON parsing: missing file creates new

    func testMissingFileInstallCreatesNew() throws {
        // Ensure file doesn't exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsFilePath))

        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)
        let result = try manager.installHooks()

        XCTAssertTrue(result.installed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsFilePath))
    }

    // MARK: - 11. Settings JSON parsing: malformed file produces error

    func testMalformedSettingsFileProducesError() throws {
        // Write invalid JSON
        try "this is not json {{{".data(using: .utf8)!
            .write(to: URL(fileURLWithPath: settingsFilePath))

        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)

        XCTAssertThrowsError(try manager.installHooks()) { error in
            guard let hooksError = error as? HooksError else {
                XCTFail("Expected HooksError, got \(error)")
                return
            }
            if case .malformedSettingsFile = hooksError {
                // Expected
            } else {
                XCTFail("Expected .malformedSettingsFile, got \(hooksError)")
            }
        }
    }

    // MARK: - 12. Integration: install -> status -> uninstall -> status

    func testFullLifecycleIntegration() throws {
        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)

        // Step 1: Not installed
        let initialStatus = try manager.hooksStatus()
        XCTAssertFalse(initialStatus.installed)

        // Step 2: Install
        let installResult = try manager.installHooks()
        XCTAssertTrue(installResult.installed)

        // Step 3: Status shows installed
        let afterInstallStatus = try manager.hooksStatus()
        XCTAssertTrue(afterInstallStatus.installed)
        XCTAssertEqual(afterInstallStatus.installedEvents.count, ClaudeSettingsManager.hookedEventTypes.count)

        // Step 4: Uninstall
        let uninstallResult = try manager.uninstallHooks()
        XCTAssertTrue(uninstallResult.uninstalled)

        // Step 5: Status shows not installed
        let afterUninstallStatus = try manager.hooksStatus()
        XCTAssertFalse(afterUninstallStatus.installed)
        XCTAssertTrue(afterUninstallStatus.installedEvents.isEmpty)
    }

    // MARK: - 13. Install detects hooks with quoted paths (AppDelegate format)

    func testInstallDetectsQuotedPathHooks() throws {
        // Simulate hooks written by AppDelegate (quoted path for shell safety).
        let appDelegateSettings: [String: Any] = [
            "hooks": ClaudeSettingsManager.hookedEventTypes.reduce(into: [String: Any]()) { dict, event in
                dict[event] = [
                    [
                        "matcher": "",
                        "hooks": [
                            [
                                "type": "command",
                                "command": "'/Applications/Cocxy Terminal.app/Contents/Resources/cocxy' hook-handler"
                            ]
                        ]
                    ]
                ]
            }
        ]
        let data = try JSONSerialization.data(withJSONObject: appDelegateSettings, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: settingsFilePath))

        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)

        // CLI install should detect the quoted hooks and NOT add duplicates.
        let result = try manager.installHooks()
        XCTAssertFalse(result.installed)
        XCTAssertTrue(result.alreadyInstalled)

        // Verify only 1 entry per event type (no duplication).
        let readData = try Data(contentsOf: URL(fileURLWithPath: settingsFilePath))
        let settings = try JSONSerialization.jsonObject(with: readData) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        for eventType in ClaudeSettingsManager.hookedEventTypes {
            let eventHooks = hooks[eventType] as! [[String: Any]]
            XCTAssertEqual(eventHooks.count, 1, "Expected exactly 1 hook for \(eventType), got \(eventHooks.count)")
        }
    }

    // MARK: - 14. Uninstall removes hooks with quoted paths

    func testUninstallRemovesQuotedPathHooks() throws {
        // Simulate hooks written by AppDelegate (quoted path).
        let appDelegateSettings: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "",
                        "hooks": [
                            [
                                "type": "command",
                                "command": "'/Applications/Cocxy Terminal.app/Contents/Resources/cocxy' hook-handler"
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: appDelegateSettings, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: settingsFilePath))

        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)
        let result = try manager.uninstallHooks()

        XCTAssertTrue(result.uninstalled)
        XCTAssertTrue(result.removedEvents.contains("Stop"))
    }

    // MARK: - 15. Install preserves non-hook settings

    func testInstallPreservesNonHookSettings() throws {
        // Write settings with permissions and other fields
        let existingSettings: [String: Any] = [
            "permissions": [
                "allow": ["/usr/bin/git"],
                "deny": ["/etc/passwd"]
            ],
            "model": "claude-sonnet-4-20250514"
        ]
        let data = try JSONSerialization.data(withJSONObject: existingSettings, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: settingsFilePath))

        let manager = ClaudeSettingsManager(settingsFilePath: settingsFilePath)
        _ = try manager.installHooks()

        // Read back and verify non-hook settings are preserved
        let readData = try Data(contentsOf: URL(fileURLWithPath: settingsFilePath))
        let settings = try JSONSerialization.jsonObject(with: readData) as! [String: Any]

        XCTAssertNotNil(settings["permissions"])
        XCTAssertNotNil(settings["model"])
        XCTAssertNotNil(settings["hooks"]) // New hooks added

        let permissions = settings["permissions"] as! [String: Any]
        let allowList = permissions["allow"] as! [String]
        XCTAssertTrue(allowList.contains("/usr/bin/git"))
    }
}

// MARK: - Hook Handler Tests

/// Tests for `HookHandlerCommand`: validates stdin JSON parsing
/// and socket request building.
final class HookHandlerTests: XCTestCase {

    // MARK: - 14. Valid JSON stdin builds correct socket request

    func testValidJSONStdinBuildsCorrectRequest() throws {
        let inputJSON = """
        {
            "type": "Stop",
            "session_id": "abc-123",
            "timestamp": "2026-03-17T10:00:00Z",
            "data": {"reason": "end_turn"}
        }
        """
        let inputData = inputJSON.data(using: .utf8)!

        let request = try HookHandlerCommand.buildRequest(from: inputData)

        XCTAssertEqual(request.command, "hook-event")
        XCTAssertNotNil(request.params)
        XCTAssertNotNil(request.params?["payload"])
        // The payload should contain the original JSON
        XCTAssertTrue(request.params!["payload"]!.contains("Stop"))
        XCTAssertTrue(request.params!["payload"]!.contains("abc-123"))
    }

    // MARK: - 15. Invalid JSON stdin produces graceful error

    func testInvalidJSONStdinProducesGracefulError() {
        let invalidData = "not json at all{{{".data(using: .utf8)!

        XCTAssertThrowsError(try HookHandlerCommand.buildRequest(from: invalidData)) { error in
            guard let hooksError = error as? HooksError else {
                XCTFail("Expected HooksError, got \(error)")
                return
            }
            if case .invalidHookJSON = hooksError {
                // Expected
            } else {
                XCTFail("Expected .invalidHookJSON, got \(hooksError)")
            }
        }
    }

    // MARK: - 16. Empty stdin produces graceful error

    func testEmptyStdinProducesGracefulError() {
        let emptyData = Data()

        XCTAssertThrowsError(try HookHandlerCommand.buildRequest(from: emptyData)) { error in
            guard let hooksError = error as? HooksError else {
                XCTFail("Expected HooksError, got \(error)")
                return
            }
            if case .emptyInput = hooksError {
                // Expected
            } else {
                XCTFail("Expected .emptyInput, got \(hooksError)")
            }
        }
    }
}

// MARK: - Hooks CLI Parsing Tests

/// Tests for parsing hooks subcommands and hook-handler command
/// through the CLI argument parser.
final class HooksCLIParsingTests: XCTestCase {

    // MARK: - 17. Parse hooks install

    func testParseHooksInstall() throws {
        let result = try CLIArgumentParser.parse(["hooks", "install"])
        XCTAssertEqual(result, .hooksInstall)
    }

    // MARK: - 18. Parse hooks uninstall

    func testParseHooksUninstall() throws {
        let result = try CLIArgumentParser.parse(["hooks", "uninstall"])
        XCTAssertEqual(result, .hooksUninstall)
    }

    // MARK: - 19. Parse hooks status

    func testParseHooksStatus() throws {
        let result = try CLIArgumentParser.parse(["hooks", "status"])
        XCTAssertEqual(result, .hooksStatus)
    }

    // MARK: - 20. Parse hooks without subcommand shows hooks help

    func testParseHooksWithoutSubcommand() throws {
        let result = try CLIArgumentParser.parse(["hooks"])
        XCTAssertEqual(result, .hooksStatus)
    }

    // MARK: - 21. Parse hook-handler

    func testParseHookHandler() throws {
        let result = try CLIArgumentParser.parse(["hook-handler"])
        XCTAssertEqual(result, .hookHandler)
    }

    // MARK: - 22. Parse hooks with unknown subcommand

    func testParseHooksWithUnknownSubcommand() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["hooks", "foobar"])
        ) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            if case .invalidArgument = cliError {
                // Expected
            } else {
                XCTFail("Expected .invalidArgument, got \(cliError)")
            }
        }
    }

    // MARK: - 23. CLICommand enum includes hooks

    func testCLICommandEnumIncludesHooks() {
        XCTAssertNotNil(CLICommand(rawValue: "hooks"))
        XCTAssertEqual(CLICommand.hooks.rawValue, "hooks")
    }

    // MARK: - 24. CLICommand enum includes hook-handler

    func testCLICommandEnumIncludesHookHandler() {
        XCTAssertNotNil(CLICommand(rawValue: "hook-handler"))
        XCTAssertEqual(CLICommand.hookHandler.rawValue, "hook-handler")
    }

    // MARK: - 25. Help text includes hooks commands

    func testHelpTextIncludesHooksCommands() {
        let helpText = CLIArgumentParser.helpText()
        XCTAssertTrue(helpText.contains("hooks"))
        XCTAssertTrue(helpText.contains("hook-handler"))
    }
}
