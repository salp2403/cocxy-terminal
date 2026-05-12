// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCLILib

@Suite("Agent hook parity")
struct AgentHooksParitySwiftTestingTests {

    @Test("AgentSource detects each supported agent from environment or payload")
    func detectsAgentSource() {
        #expect(AgentSource.detect(environment: ["CLAUDE_SESSION_ID": "claude-1"]) == .claudeCode)
        #expect(AgentSource.detect(environment: ["CODEX_THREAD_ID": "codex-1"]) == .codex)
        #expect(AgentSource.detect(environment: ["GEMINI_SESSION_ID": "gemini-1"]) == .geminiCLI)
        #expect(AgentSource.detect(environment: ["KIRO_SESSION_ID": "kiro-1"]) == .kiro)
        #expect(AgentSource.detect(environment: ["OPENCODE_SESSION_ID": "opencode-1"]) == .opencode)
        #expect(AgentSource.detect(environment: ["PI_SESSION_ID": "pi-1"]) == .pi)
        #expect(AgentSource.detect(environment: ["CURSOR_SESSION_ID": "cursor-1"]) == .cursor)
        #expect(AgentSource.detect(environment: ["ROVODEV_SESSION_ID": "rovo-1"]) == .rovoDev)
        #expect(AgentSource.detect(environment: ["COPILOT_SESSION_ID": "copilot-1"]) == .copilot)
        #expect(AgentSource.detect(environment: ["CODEBUDDY_SESSION_ID": "codebuddy-1"]) == .codebuddy)
        #expect(AgentSource.detect(environment: ["FACTORY_SESSION_ID": "factory-1"]) == .factory)
        #expect(AgentSource.detect(environment: ["QODER_SESSION_ID": "qoder-1"]) == .qoder)
        #expect(AgentSource.detect(environment: [:], payload: ["hook_event_name": "BeforeTool"]) == .geminiCLI)
        #expect(AgentSource.detect(environment: [:], payload: ["hook_event_name": "agentSpawn"]) == .kiro)
        #expect(AgentSource.detect(environment: [:], payload: [:]) == .unknown)
    }

    @Test("HookEventNormalizer canonicalizes Gemini and Kiro payloads")
    func normalizesForeignPayloads() throws {
        let geminiData = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "BeforeTool",
            "tool_name": "run_shell_command"
        ])
        let normalizedGemini = try HookEventNormalizer.normalizePayload(
            geminiData,
            environment: [
                "GEMINI_SESSION_ID": "gemini-session",
                "PWD": "/tmp/gemini"
            ]
        )
        let geminiPayload = try #require(
            try JSONSerialization.jsonObject(with: normalizedGemini) as? [String: Any]
        )
        #expect(geminiPayload["hook_event_name"] as? String == "PreToolUse")
        #expect(geminiPayload["session_id"] as? String == "gemini-session")
        #expect(geminiPayload["cwd"] as? String == "/tmp/gemini")

        let kiroData = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "agentSpawn",
            "cwd": "/tmp/kiro"
        ])
        let normalizedKiro = try HookEventNormalizer.normalizePayload(
            kiroData,
            environment: [
                "TERM_SESSION_ID": "term-123",
                "PPID": "456",
                "PWD": "/tmp/kiro"
            ]
        )
        let kiroPayload = try #require(
            try JSONSerialization.jsonObject(with: normalizedKiro) as? [String: Any]
        )
        #expect(kiroPayload["hook_event_name"] as? String == "SessionStart")
        #expect(kiroPayload["cwd"] as? String == "/tmp/kiro")
        #expect(kiroPayload["agent_type"] as? String == "kiro")
        #expect((kiroPayload["session_id"] as? String)?.hasPrefix("kiro-") == true)
    }

    @Test("HookHandlerCommand builds normalized payloads for Codex")
    func buildRequestNormalizesCodexPayload() throws {
        let data = Data("""
        {
            "hook_event_name": "SessionStart",
            "cwd": "/tmp/codex"
        }
        """.utf8)

        let request = try HookHandlerCommand.buildRequest(
            from: data,
            environment: [
                "COCXY_CLAUDE_HOOKS": "1",
                "CODEX_THREAD_ID": "codex-thread-1",
                "PWD": "/tmp/codex"
            ]
        )

        #expect(request.command == "hook-event")
        let payloadString = try #require(request.params?["payload"])
        let payloadData = Data(payloadString.utf8)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        )
        #expect(payload["hook_event_name"] as? String == "SessionStart")
        #expect(payload["session_id"] as? String == "codex-thread-1")
        #expect(payload["agent_type"] as? String == "codex")
        #expect(payload["cwd"] as? String == "/tmp/codex")
    }

    @Test("Forced hook agent marker disambiguates Gemini SessionStart")
    func forcedHookAgentDisambiguatesGeminiSessionStart() throws {
        let data = Data("""
        {
            "hook_event_name": "SessionStart",
            "session_id": "gemini-session-1",
            "cwd": "/tmp/gemini"
        }
        """.utf8)

        let request = try HookHandlerCommand.buildRequest(
            from: data,
            environment: [
                "COCXY_CLAUDE_HOOKS": "1",
                "COCXY_HOOK_AGENT": "gemini",
                "PWD": "/tmp/gemini"
            ]
        )

        let payloadString = try #require(request.params?["payload"])
        let payload = try #require(
            try JSONSerialization.jsonObject(with: Data(payloadString.utf8)) as? [String: Any]
        )
        #expect(payload["agent_type"] as? String == "gemini-cli")
        #expect(payload["session_id"] as? String == "gemini-session-1")
    }

    @Test("setup-hooks parser accepts agent filters and remove flag")
    func parsesSetupHooksCommand() throws {
        #expect(
            try CLIArgumentParser.parse(["setup-hooks"]) == .setupHooks(
                agent: nil,
                remove: false,
                dryRun: false,
                check: false,
                opencodeProject: false
            )
        )
        #expect(
            try CLIArgumentParser.parse(["setup-hooks", "--agent", "codex"]) == .setupHooks(
                agent: .codex,
                remove: false,
                dryRun: false,
                check: false,
                opencodeProject: false
            )
        )
        #expect(
            try CLIArgumentParser.parse(["setup-hooks", "--agent", "opencode"]) == .setupHooks(
                agent: .opencode,
                remove: false,
                dryRun: false,
                check: false,
                opencodeProject: false
            )
        )
        #expect(
            try CLIArgumentParser.parse(["setup-hooks", "--agent", "qoder"]) == .setupHooks(
                agent: .qoder,
                remove: false,
                dryRun: false,
                check: false,
                opencodeProject: false
            )
        )
        #expect(
            try CLIArgumentParser.parse(["setup-hooks", "--agent", "rovo-dev"]) == .setupHooks(
                agent: .rovoDev,
                remove: false,
                dryRun: false,
                check: false,
                opencodeProject: false
            )
        )
        #expect(
            try CLIArgumentParser.parse(["setup-hooks", "--agent", "all", "--remove"]) == .setupHooks(
                agent: .all,
                remove: true,
                dryRun: false,
                check: false,
                opencodeProject: false
            )
        )
        #expect(
            try CLIArgumentParser.parse(["setup-hooks", "--agent", "qoder", "--dry-run"]) == .setupHooks(
                agent: .qoder,
                remove: false,
                dryRun: true,
                check: false,
                opencodeProject: false
            )
        )
        #expect(
            try CLIArgumentParser.parse(["setup-hooks", "--agent", "qoder", "--remove", "--dry-run"]) == .setupHooks(
                agent: .qoder,
                remove: true,
                dryRun: true,
                check: false,
                opencodeProject: false
            )
        )
        #expect(
            try CLIArgumentParser.parse(["setup-hooks", "--agent", "qoder", "--check"]) == .setupHooks(
                agent: .qoder,
                remove: false,
                dryRun: false,
                check: true,
                opencodeProject: false
            )
        )
        #expect(
            try CLIArgumentParser.parse(["setup-hooks", "--opencode-project"]) == .setupHooks(
                agent: nil,
                remove: false,
                dryRun: false,
                check: false,
                opencodeProject: true
            )
        )
    }

    @Test("setup-hooks detects installed agent binaries from commandExists")
    func detectsInstalledAgentsForSetup() {
        let detected = SetupHooksCommand.detectInstalledAgents { command in
            ["claude", "codex", "opencode", "qodercli", "kiro-cli"].contains(command)
        }
        #expect(detected == [.claudeCode, .codex, .kiro, .opencode, .qoder])
    }

    @Test("ClaudeSettingsManager creates a backup before modifying settings")
    func claudeManagerCreatesBackup() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsPath = tempDirectory.appendingPathComponent("settings.json").path
        let initialJSON = """
        {
          "theme": "dark",
          "hooks": {}
        }
        """
        try initialJSON.write(toFile: settingsPath, atomically: true, encoding: .utf8)

        let manager = ClaudeSettingsManager(settingsFilePath: settingsPath)
        let result = try manager.installHooks()

        #expect(result.installed)
        #expect(FileManager.default.fileExists(atPath: settingsPath + ".cocxy-backup"))
    }

    @Test("ClaudeSettingsManager rewrites stale bundle hook paths instead of treating them as installed")
    func claudeManagerRewritesStaleBundleHookPaths() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsPath = tempDirectory.appendingPathComponent("settings.json").path
        let staleCommand = "'/private/tmp/CocxyTerminalSmoke.app/Contents/Resources/cocxy' hook-handler"
        let initialSettings: [String: Any] = [
            "hooks": ClaudeSettingsManager.hookedEventTypes.reduce(into: [String: Any]()) { dict, event in
                dict[event] = [
                    [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": staleCommand]
                        ]
                    ]
                ]
            }
        ]
        let initialData = try JSONSerialization.data(withJSONObject: initialSettings, options: .prettyPrinted)
        try initialData.write(to: URL(fileURLWithPath: settingsPath))

        let manager = ClaudeSettingsManager(settingsFilePath: settingsPath)
        let result = try manager.installHooks()

        #expect(result.installed)

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        for event in ClaudeSettingsManager.hookedEventTypes {
            let entries = try #require(hooks[event] as? [[String: Any]])
            #expect(entries.count == 1)
            let commands = try #require(entries[0]["hooks"] as? [[String: Any]])
            #expect(commands.first?["command"] as? String == ClaudeSettingsManager.cocxyHookCommand)
            #expect(commands.first?["command"] as? String != staleCommand)
        }
    }

    @Test("ClaudeSettingsManager preserves user hook wrappers that are not stale app bundle paths")
    func claudeManagerPreservesCustomHookWrapper() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsPath = tempDirectory.appendingPathComponent("settings.json").path
        let wrapperCommand = "/usr/local/bin/cocxy-wrapper hook-handler"
        let initialSettings: [String: Any] = [
            "hooks": ClaudeSettingsManager.hookedEventTypes.reduce(into: [String: Any]()) { dict, event in
                dict[event] = [
                    [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": wrapperCommand]
                        ]
                    ]
                ]
            }
        ]
        let initialData = try JSONSerialization.data(withJSONObject: initialSettings, options: .prettyPrinted)
        try initialData.write(to: URL(fileURLWithPath: settingsPath))

        let manager = ClaudeSettingsManager(settingsFilePath: settingsPath)
        let result = try manager.installHooks()

        #expect(result.alreadyInstalled)

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let stopEntries = try #require(hooks["Stop"] as? [[String: Any]])
        let commands = try #require(stopEntries[0]["hooks"] as? [[String: Any]])
        #expect(commands.first?["command"] as? String == wrapperCommand)
    }

    @Test("ClaudeSettingsManager preserves custom wrappers while repairing other events")
    func claudeManagerPreservesCustomWrapperDuringPartialRepair() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsPath = tempDirectory.appendingPathComponent("settings.json").path
        let wrapperCommand = "/usr/local/bin/cocxy-wrapper hook-handler"
        let initialSettings: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": wrapperCommand]
                        ]
                    ]
                ]
            ]
        ]
        let initialData = try JSONSerialization.data(withJSONObject: initialSettings, options: .prettyPrinted)
        try initialData.write(to: URL(fileURLWithPath: settingsPath))

        let manager = ClaudeSettingsManager(settingsFilePath: settingsPath)
        let result = try manager.installHooks()

        #expect(result.installed)

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let stopEntries = try #require(hooks["Stop"] as? [[String: Any]])
        let stopCommands = try #require(stopEntries[0]["hooks"] as? [[String: Any]])
        #expect(stopCommands.first?["command"] as? String == wrapperCommand)

        let sessionStartEntries = try #require(hooks["SessionStart"] as? [[String: Any]])
        let sessionStartCommands = try #require(sessionStartEntries[0]["hooks"] as? [[String: Any]])
        #expect(sessionStartCommands.first?["command"] as? String == ClaudeSettingsManager.cocxyHookCommand)
    }

    @Test("Grouped hooks require the expected forced agent marker")
    func groupedHooksRewriteWrappersMissingForcedAgentMarker() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsPath = tempDirectory.appendingPathComponent("hooks.json").path
        let initialJSON = """
        {
          "hooks": {
            "SessionStart": [
              {
                "matcher": "",
                "hooks": [
                  { "type": "command", "command": "/usr/local/bin/cocxy-wrapper hook-handler" }
                ]
              }
            ]
          }
        }
        """
        try initialJSON.write(toFile: settingsPath, atomically: true, encoding: .utf8)

        let manager = GroupedHooksSettingsManager(
            settingsFilePath: settingsPath,
            hookEvents: ["SessionStart"],
            hookCommand: ClaudeSettingsManager.hookCommand(for: .codex)
        )

        let result = try manager.installHooks()

        #expect(result.installed)

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let entries = try #require(hooks["SessionStart"] as? [[String: Any]])
        let commands = try #require(entries[0]["hooks"] as? [[String: Any]])
        #expect((commands.first?["command"] as? String)?.contains("COCXY_HOOK_AGENT=codex") == true)
    }

    @Test("Grouped hooks preserve custom wrappers when the forced agent marker is present")
    func groupedHooksPreserveWrappersWithForcedAgentMarker() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsPath = tempDirectory.appendingPathComponent("hooks.json").path
        let wrapperCommand = "COCXY_HOOK_AGENT=codex /usr/local/bin/cocxy-wrapper hook-handler"
        let initialJSON = """
        {
          "hooks": {
            "SessionStart": [
              {
                "matcher": "",
                "hooks": [
                  { "type": "command", "command": "\(wrapperCommand)" }
                ]
              }
            ]
          }
        }
        """
        try initialJSON.write(toFile: settingsPath, atomically: true, encoding: .utf8)

        let manager = GroupedHooksSettingsManager(
            settingsFilePath: settingsPath,
            hookEvents: ["SessionStart"],
            hookCommand: ClaudeSettingsManager.hookCommand(for: .codex)
        )

        let result = try manager.installHooks()

        #expect(result.alreadyInstalled)

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let entries = try #require(hooks["SessionStart"] as? [[String: Any]])
        let commands = try #require(entries[0]["hooks"] as? [[String: Any]])
        #expect(commands.first?["command"] as? String == wrapperCommand)
    }

    @Test("Grouped hooks preserve custom wrappers while repairing other events")
    func groupedHooksPreserveWrapperDuringPartialRepair() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsPath = tempDirectory.appendingPathComponent("hooks.json").path
        let wrapperCommand = "COCXY_HOOK_AGENT=codex /usr/local/bin/cocxy-wrapper hook-handler"
        let initialJSON = """
        {
          "hooks": {
            "SessionStart": [
              {
                "matcher": "",
                "hooks": [
                  { "type": "command", "command": "\(wrapperCommand)" }
                ]
              }
            ]
          }
        }
        """
        try initialJSON.write(toFile: settingsPath, atomically: true, encoding: .utf8)

        let manager = GroupedHooksSettingsManager(
            settingsFilePath: settingsPath,
            hookEvents: ["SessionStart", "Stop"],
            hookCommand: ClaudeSettingsManager.hookCommand(for: .codex)
        )

        let result = try manager.installHooks()

        #expect(result.installed)

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let sessionStartEntries = try #require(hooks["SessionStart"] as? [[String: Any]])
        let sessionStartCommands = try #require(sessionStartEntries[0]["hooks"] as? [[String: Any]])
        #expect(sessionStartCommands.first?["command"] as? String == wrapperCommand)

        let stopEntries = try #require(hooks["Stop"] as? [[String: Any]])
        let stopCommands = try #require(stopEntries[0]["hooks"] as? [[String: Any]])
        #expect((stopCommands.first?["command"] as? String)?.contains("COCXY_HOOK_AGENT=codex") == true)
    }

    @Test("Hook command avoids temporary app bundle paths when an installed app is available")
    func hookCommandPrefersInstalledAppOverTemporaryBundle() {
        let command = ClaudeSettingsManager.hookCommand(
            forExecutablePath: "/private/tmp/CocxyTerminalSmoke.app/Contents/Resources/cocxy",
            fileExists: { $0 == ClaudeSettingsManager.installedAppCLIPath }
        )

        #expect(command == "'/Applications/Cocxy Terminal.app/Contents/Resources/cocxy' hook-handler")
    }

    @Test("Hook command falls back to PATH when only a temporary app bundle is available")
    func hookCommandFallsBackForTemporaryBundleWithoutInstalledApp() {
        let command = ClaudeSettingsManager.hookCommand(
            forExecutablePath: "/private/tmp/CocxyTerminalSmoke.app/Contents/Resources/cocxy",
            fileExists: { _ in false }
        )

        #expect(command == "cocxy hook-handler")
    }

    @Test("GroupedHooksSettingsManager merges idempotently and preserves user hooks")
    func groupedManagerMergeAndBackup() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsPath = tempDirectory.appendingPathComponent("hooks.json").path
        let initialJSON = """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "^bash$",
                "hooks": [
                  { "type": "command", "command": "echo existing" }
                ]
              }
            ]
          }
        }
        """
        try initialJSON.write(toFile: settingsPath, atomically: true, encoding: .utf8)

        let manager = GroupedHooksSettingsManager(
            settingsFilePath: settingsPath,
            hookEvents: ["PreToolUse", "PostToolUse", "SessionStart"]
        )

        let installResult = try manager.installHooks()
        #expect(installResult.installed)
        #expect(FileManager.default.fileExists(atPath: settingsPath + ".cocxy-backup"))

        let status = try manager.hooksStatus()
        #expect(status.installed)
        #expect(status.installedEvents == ["PreToolUse", "PostToolUse", "SessionStart"])

        let reinstall = try manager.installHooks()
        #expect(reinstall.alreadyInstalled)

        let settingsData = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: settingsData) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let preToolHooks = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(preToolHooks.count == 2)

        let uninstallResult = try manager.uninstallHooks()
        #expect(uninstallResult.uninstalled)

        let postUninstallData = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let postUninstallSettings = try #require(
            try JSONSerialization.jsonObject(with: postUninstallData) as? [String: Any]
        )
        let postUninstallHooks = try #require(postUninstallSettings["hooks"] as? [String: Any])
        let survivingPreToolHooks = try #require(postUninstallHooks["PreToolUse"] as? [[String: Any]])
        #expect(survivingPreToolHooks.count == 1)
    }

    @Test("setup-hooks reports Kiro manual wiring requirement")
    func setupHooksReportsKiroManualRequirement() {
        let result = SetupHooksCommand.execute(
            target: .kiro,
            remove: false,
            commandExists: { _ in true }
        )

        #expect(result.exitCode == 1)
        #expect(result.stdout.contains("Kiro"))
        #expect(result.stdout.contains("manual"))
    }

    @Test("setup-hooks reports manual wiring for expanded agents without JSON managers")
    func setupHooksReportsManualWiringForExpandedAgentsWithoutJSONManagers() {
        let result = SetupHooksCommand.execute(
            target: .opencode,
            remove: false,
            commandExists: { _ in true }
        )

        #expect(result.exitCode == 1)
        #expect(result.stdout.contains("OpenCode"))
        #expect(result.stdout.contains("manual"))
    }

    @Test("setup-hooks installs JSON hook agents with forced agent marker and preserves user hooks")
    func setupHooksInstallsJSONHookAgentWithForcedMarker() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsPath = tempDirectory.appendingPathComponent("settings.json").path
        let initialJSON = """
        {
          "hooks": {
            "SessionStart": [
              {
                "matcher": "user",
                "hooks": [
                  { "type": "command", "command": "echo keep-user-hook" }
                ]
              }
            ]
          }
        }
        """
        try initialJSON.write(toFile: settingsPath, atomically: true, encoding: .utf8)

        let result = SetupHooksCommand.execute(
            target: .qoder,
            remove: false,
            commandExists: { _ in true },
            settingsFilePathResolver: { source in
                source == .qoder ? settingsPath : source.hookSettingsFilePath
            }
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Qoder"))
        #expect(result.stdout.contains("hooks installed"))

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let sessionStartEntries = try #require(hooks["SessionStart"] as? [[String: Any]])
        #expect(sessionStartEntries.count == 2)
        let commands = sessionStartEntries.compactMap { entry -> String? in
            guard let hookCommands = entry["hooks"] as? [[String: Any]] else { return nil }
            return hookCommands.first?["command"] as? String
        }
        #expect(commands.contains("echo keep-user-hook"))
        #expect(commands.contains(where: { $0.contains("COCXY_HOOK_AGENT=qoder") }))
        #expect(FileManager.default.fileExists(atPath: settingsPath + ".cocxy-backup"))
    }

    @Test("setup-hooks removes JSON hook agents without deleting user hooks")
    func setupHooksRemovesJSONHookAgentWithoutDeletingUserHooks() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsPath = tempDirectory.appendingPathComponent("settings.json").path
        let initialJSON = """
        {
          "hooks": {
            "SessionStart": [
              {
                "matcher": "user",
                "hooks": [
                  { "type": "command", "command": "echo keep-user-hook" }
                ]
              }
            ]
          }
        }
        """
        try initialJSON.write(toFile: settingsPath, atomically: true, encoding: .utf8)

        let resolver: (AgentSource) -> String? = { source in
            source == .qoder ? settingsPath : source.hookSettingsFilePath
        }

        _ = SetupHooksCommand.execute(
            target: .qoder,
            remove: false,
            commandExists: { _ in true },
            settingsFilePathResolver: resolver
        )

        let result = SetupHooksCommand.execute(
            target: .qoder,
            remove: true,
            commandExists: { _ in true },
            settingsFilePathResolver: resolver
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Qoder"))
        #expect(result.stdout.contains("hooks removed"))

        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        let settings = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let sessionStartEntries = try #require(hooks["SessionStart"] as? [[String: Any]])
        #expect(sessionStartEntries.count == 1)
        let commands = sessionStartEntries.compactMap { entry -> String? in
            guard let hookCommands = entry["hooks"] as? [[String: Any]] else { return nil }
            return hookCommands.first?["command"] as? String
        }
        #expect(commands == ["echo keep-user-hook"])
        #expect(commands.allSatisfy { !$0.contains("COCXY_HOOK_AGENT=qoder") })
    }

    @Test("setup-hooks dry-run previews JSON hook changes without writing files")
    func setupHooksDryRunPreviewsJSONHookChangesWithoutWritingFiles() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let initialJSON = """
        {
          "hooks": {}
        }
        """
        try initialJSON.write(to: settingsURL, atomically: true, encoding: .utf8)

        let result = SetupHooksCommand.execute(
            target: .qoder,
            remove: false,
            dryRun: true,
            commandExists: { _ in true },
            settingsFilePathResolver: { source in
                source == .qoder ? settingsURL.path : source.hookSettingsFilePath
            }
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Dry run"))
        #expect(result.stdout.contains("Qoder"))
        #expect(result.stdout.contains("would install"))
        #expect(result.stdout.contains(settingsURL.path))
        #expect(try String(contentsOf: settingsURL, encoding: .utf8) == initialJSON)
        #expect(!FileManager.default.fileExists(atPath: settingsURL.path + ".cocxy-backup"))
    }

    @Test("setup-hooks check reports missing JSON hook events")
    func setupHooksCheckReportsMissingJSONHookEvents() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsPath = tempDirectory.appendingPathComponent("settings.json").path
        let partialJSON = """
        {
          "hooks": {
            "SessionStart": [
              {
                "matcher": "",
                "hooks": [
                  {
                    "type": "command",
                    "command": "COCXY_HOOK_AGENT=qoder /Applications/Cocxy Terminal.app/Contents/Resources/cocxy hook-handler"
                  }
                ]
              }
            ]
          }
        }
        """
        try partialJSON.write(toFile: settingsPath, atomically: true, encoding: .utf8)

        let result = SetupHooksCommand.execute(
            target: .qoder,
            remove: false,
            check: true,
            commandExists: { _ in true },
            settingsFilePathResolver: { source in
                source == .qoder ? settingsPath : source.hookSettingsFilePath
            }
        )

        #expect(result.exitCode == 1)
        #expect(result.stdout.contains("Qoder"))
        #expect(result.stdout.contains("missing"))
        #expect(result.stdout.contains("SessionEnd"))
    }

    @Test("setup-hooks check fails when an agent cannot be verified automatically")
    func setupHooksCheckFailsWhenAgentCannotBeVerifiedAutomatically() {
        let result = SetupHooksCommand.execute(
            target: .opencode,
            remove: false,
            check: true,
            commandExists: { _ in true }
        )

        #expect(result.exitCode == 1)
        #expect(result.stdout.contains("OpenCode"))
        #expect(result.stdout.contains("integrity check is not available"))
    }

    @Test("hook conflict detector reports existing non-Cocxy command hooks without exposing commands")
    func hookConflictDetectorReportsExistingNonCocxyCommandHooksWithoutExposingCommands() throws {
        let settings: [String: Any] = [
            "hooks": [
                "SessionStart": [
                    [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": "third-party-session-tool sync"],
                            ["type": "command", "command": "COCXY_HOOK_AGENT=qoder cocxy hook-handler"]
                        ]
                    ]
                ],
                "Stop": [
                    [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": "external-stop-hook"]
                        ]
                    ]
                ]
            ]
        ]

        let conflicts = HooksConflictDetector.detect(in: settings, limitedTo: ["SessionStart", "Stop"])
        #expect(conflicts.count == 2)
        #expect(conflicts.map(\.eventType).sorted() == ["SessionStart", "Stop"])

        let warning = try #require(HooksConflictDetector.warning(for: conflicts))
        #expect(warning.contains("existing non-Cocxy hooks"))
        #expect(warning.contains("SessionStart"))
        #expect(warning.contains("Stop"))
        #expect(!warning.contains("third-party-session-tool"))
        #expect(!warning.contains("external-stop-hook"))
    }

    @Test("setup-hooks dry-run warns about existing non-Cocxy hooks and preserves the file")
    func setupHooksDryRunWarnsAboutExistingNonCocxyHooksAndPreservesFile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let initialJSON = """
        {
          "hooks": {
            "SessionStart": [
              {
                "matcher": "",
                "hooks": [
                  { "type": "command", "command": "third-party-session-tool sync" }
                ]
              }
            ]
          }
        }
        """
        try initialJSON.write(to: settingsURL, atomically: true, encoding: .utf8)

        let result = SetupHooksCommand.execute(
            target: .qoder,
            remove: false,
            dryRun: true,
            commandExists: { _ in true },
            settingsFilePathResolver: { source in
                source == .qoder ? settingsURL.path : source.hookSettingsFilePath
            }
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("existing non-Cocxy hooks"))
        #expect(result.stdout.contains("would install"))
        #expect(!result.stdout.contains("third-party-session-tool"))
        #expect(try String(contentsOf: settingsURL, encoding: .utf8) == initialJSON)
    }

    @Test("setup-hooks installs OpenCode project bridge plugin")
    func setupHooksInstallsOpenCodeProjectBridgePlugin() throws {
        let projectDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectDirectory) }

        let result = SetupHooksCommand.execute(
            target: nil,
            remove: false,
            opencodeProject: true,
            projectDirectory: projectDirectory,
            commandExists: { _ in true }
        )

        let pluginURL = projectDirectory.appendingPathComponent(".opencode/plugins/cocxy-session.js")
        let plugin = try String(contentsOf: pluginURL, encoding: .utf8)
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("OpenCode"))
        #expect(result.stdout.contains("project plugin installed"))
        #expect(plugin.contains("Cocxy managed OpenCode session bridge"))
        #expect(plugin.contains("hook-handler"))
        #expect(plugin.contains("shell.env"))
        #expect(plugin.contains("tool.execute.before"))
        #expect(plugin.contains("tool.execute.after"))
    }

    @Test("setup-hooks dry-run previews OpenCode project bridge without writing")
    func setupHooksDryRunPreviewsOpenCodeProjectBridgeWithoutWriting() throws {
        let projectDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectDirectory) }

        let result = SetupHooksCommand.execute(
            target: nil,
            remove: false,
            dryRun: true,
            opencodeProject: true,
            projectDirectory: projectDirectory,
            commandExists: { _ in true }
        )

        let pluginURL = projectDirectory.appendingPathComponent(".opencode/plugins/cocxy-session.js")
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("Dry run"))
        #expect(result.stdout.contains(pluginURL.path))
        #expect(!FileManager.default.fileExists(atPath: pluginURL.path))
    }

    @Test("setup-hooks check verifies OpenCode project bridge plugin")
    func setupHooksCheckVerifiesOpenCodeProjectBridgePlugin() throws {
        let projectDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectDirectory) }

        let missing = SetupHooksCommand.execute(
            target: nil,
            remove: false,
            check: true,
            opencodeProject: true,
            projectDirectory: projectDirectory,
            commandExists: { _ in true }
        )
        #expect(missing.exitCode == 1)
        #expect(missing.stdout.contains("project plugin missing"))

        _ = SetupHooksCommand.execute(
            target: nil,
            remove: false,
            opencodeProject: true,
            projectDirectory: projectDirectory,
            commandExists: { _ in true }
        )

        let installed = SetupHooksCommand.execute(
            target: nil,
            remove: false,
            check: true,
            opencodeProject: true,
            projectDirectory: projectDirectory,
            commandExists: { _ in true }
        )
        #expect(installed.exitCode == 0)
        #expect(installed.stdout.contains("project plugin OK"))
    }

    @Test("setup-hooks installs and removes Pi extension hooks")
    func setupHooksInstallsAndRemovesPiExtensionHooks() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let extensionPath = tempDirectory.appendingPathComponent(".pi/agent/extensions/cocxy-session.ts").path
        let resolver: (AgentSource) -> String? = { source in
            source == .pi ? extensionPath : source.hookSettingsFilePath
        }

        let install = SetupHooksCommand.execute(
            target: .pi,
            remove: false,
            commandExists: { _ in true },
            settingsFilePathResolver: resolver
        )

        #expect(install.exitCode == 0)
        #expect(install.stdout.contains("Pi"))
        #expect(install.stdout.contains("hooks installed"))

        let extensionSource = try String(contentsOfFile: extensionPath, encoding: .utf8)
        #expect(extensionSource.contains("Cocxy managed Pi session bridge"))
        #expect(extensionSource.contains("session_start"))
        #expect(extensionSource.contains("tool_call"))
        #expect(extensionSource.contains("session_shutdown"))
        #expect(extensionSource.contains("COCXY_PI_HOOKS_DISABLED"))
        #expect(extensionSource.contains("hook-handler"))

        let check = SetupHooksCommand.execute(
            target: .pi,
            remove: false,
            check: true,
            commandExists: { _ in true },
            settingsFilePathResolver: resolver
        )
        #expect(check.exitCode == 0)
        #expect(check.stdout.contains("hooks OK"))

        let remove = SetupHooksCommand.execute(
            target: .pi,
            remove: true,
            commandExists: { _ in true },
            settingsFilePathResolver: resolver
        )
        #expect(remove.exitCode == 0)
        #expect(remove.stdout.contains("hooks removed"))
        #expect(!FileManager.default.fileExists(atPath: extensionPath))
    }

    @Test("setup-hooks refuses to overwrite non-Cocxy Pi extension")
    func setupHooksRefusesToOverwriteNonCocxyPiExtension() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let extensionURL = tempDirectory.appendingPathComponent(".pi/agent/extensions/cocxy-session.ts")
        try FileManager.default.createDirectory(at: extensionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "export default function () {}\n".write(to: extensionURL, atomically: true, encoding: .utf8)

        let result = SetupHooksCommand.execute(
            target: .pi,
            remove: false,
            commandExists: { _ in true },
            settingsFilePathResolver: { source in
                source == .pi ? extensionURL.path : source.hookSettingsFilePath
            }
        )

        #expect(result.exitCode == 1)
        #expect(result.stdout.contains("Pi"))
        #expect(result.stdout.contains("failed to update hooks"))
        #expect(try String(contentsOf: extensionURL, encoding: .utf8) == "export default function () {}\n")
    }

    @Test("setup-hooks merges and removes Rovo Dev event hooks without deleting user config")
    func setupHooksMergesAndRemovesRovoDevEventHooks() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configURL = tempDirectory.appendingPathComponent(".rovodev/config.yml")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let initialConfig = """
        theme: dark
        eventHooks:
          events:
            - name: custom
              commands:
                - command: "echo keep-user-hook"
        """
        try initialConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let resolver: (AgentSource) -> String? = { source in
            source == .rovoDev ? configURL.path : source.hookSettingsFilePath
        }

        let install = SetupHooksCommand.execute(
            target: .rovoDev,
            remove: false,
            commandExists: { _ in true },
            settingsFilePathResolver: resolver
        )

        #expect(install.exitCode == 0)
        #expect(install.stdout.contains("Rovo Dev"))
        #expect(install.stdout.contains("hooks installed"))

        let installedConfig = try String(contentsOf: configURL, encoding: .utf8)
        #expect(installedConfig.contains("echo keep-user-hook"))
        #expect(installedConfig.contains("Cocxy managed Rovo Dev hooks begin"))
        #expect(installedConfig.contains("on_complete"))
        #expect(installedConfig.contains("on_error"))
        #expect(installedConfig.contains("on_tool_permission"))
        #expect(installedConfig.contains("COCXY_HOOK_AGENT=rovo"))
        #expect(FileManager.default.fileExists(atPath: configURL.path + ".cocxy-backup"))

        let check = SetupHooksCommand.execute(
            target: .rovoDev,
            remove: false,
            check: true,
            commandExists: { _ in true },
            settingsFilePathResolver: resolver
        )
        #expect(check.exitCode == 0)
        #expect(check.stdout.contains("hooks OK"))

        let remove = SetupHooksCommand.execute(
            target: .rovoDev,
            remove: true,
            commandExists: { _ in true },
            settingsFilePathResolver: resolver
        )
        #expect(remove.exitCode == 0)
        #expect(remove.stdout.contains("hooks removed"))

        let removedConfig = try String(contentsOf: configURL, encoding: .utf8)
        #expect(removedConfig.contains("echo keep-user-hook"))
        #expect(!removedConfig.contains("Cocxy managed Rovo Dev hooks begin"))
        #expect(!removedConfig.contains("COCXY_HOOK_AGENT=rovo"))
    }

    @Test("OpenCode hook script resource matches installer template")
    func openCodeHookScriptResourceMatchesInstallerTemplate() throws {
        let resourceURL = repositoryRoot()
            .appendingPathComponent("Resources/HookScripts/opencode-cocxy-session.js")
        let resource = try String(contentsOf: resourceURL, encoding: .utf8)

        #expect(
            resource.trimmingCharacters(in: .newlines)
                == OpenCodeProjectHooksManager.pluginSource.trimmingCharacters(in: .newlines)
        )
    }

    @Test("Pi hook script resource matches installer template")
    func piHookScriptResourceMatchesInstallerTemplate() throws {
        let resourceURL = repositoryRoot()
            .appendingPathComponent("Resources/HookScripts/pi-cocxy-session.ts")
        let resource = try String(contentsOf: resourceURL, encoding: .utf8)

        #expect(
            resource.trimmingCharacters(in: .newlines)
                == PiExtensionHooksManager.extensionSource.trimmingCharacters(in: .newlines)
        )
    }

    @Test("app bundle scripts include hook script resources")
    func appBundleScriptsIncludeHookScriptResources() throws {
        let root = repositoryRoot()
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let verifyScript = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )

        #expect(buildScript.contains("Resources/HookScripts"))
        #expect(buildScript.contains("\"${RESOURCES}/HookScripts\""))
        #expect(verifyScript.contains("$RESOURCES/HookScripts/opencode-cocxy-session.js"))
        #expect(verifyScript.contains("$RESOURCES/HookScripts/pi-cocxy-session.ts"))
        #expect(verifyScript.contains("$RESOURCES/HookScripts/rovo-event-hooks.yml.template"))
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
