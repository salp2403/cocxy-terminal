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
            try CLIArgumentParser.parse(["setup-hooks"]) == .setupHooks(agent: nil, remove: false)
        )
        #expect(
            try CLIArgumentParser.parse(["setup-hooks", "--agent", "codex"]) == .setupHooks(agent: .codex, remove: false)
        )
        #expect(
            try CLIArgumentParser.parse(["setup-hooks", "--agent", "all", "--remove"]) == .setupHooks(agent: .all, remove: true)
        )
    }

    @Test("setup-hooks detects installed agent binaries from commandExists")
    func detectsInstalledAgentsForSetup() {
        let detected = SetupHooksCommand.detectInstalledAgents { command in
            ["claude", "codex", "kiro-cli"].contains(command)
        }
        #expect(detected == [.claudeCode, .codex, .kiro])
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
}
