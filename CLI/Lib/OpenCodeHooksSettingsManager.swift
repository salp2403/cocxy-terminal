// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// OpenCodeHooksSettingsManager.swift - OpenCode plugin bridge installer.

import Foundation

struct OpenCodeHooksSettingsManager {
    struct PluginTemplate {
        let fileName: String
        let marker: String
        let source: String
    }

    static let sessionMarker = "Cocxy managed OpenCode session bridge"
    static let feedMarker = "Cocxy managed OpenCode feed bridge"
    static let hookEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"]

    static let pluginTemplates: [PluginTemplate] = [
        PluginTemplate(
            fileName: "cocxy-session.js",
            marker: sessionMarker,
            source: sessionPluginSource
        ),
        PluginTemplate(
            fileName: "cocxy-feed.js",
            marker: feedMarker,
            source: feedPluginSource
        )
    ]

    let pluginsDirectoryURL: URL
    let scopeDescription: String
    let fileManager: FileManager

    init(
        pluginsDirectoryURL: URL,
        scopeDescription: String = "plugins",
        fileManager: FileManager = .default
    ) {
        self.pluginsDirectoryURL = pluginsDirectoryURL
        self.scopeDescription = scopeDescription
        self.fileManager = fileManager
    }

    func installHooks() throws -> HooksInstallResult {
        var wroteAny = false

        for template in Self.pluginTemplates {
            let url = pluginURL(for: template)
            if fileManager.fileExists(atPath: url.path) {
                let existing = try readPlugin(at: url)
                if existing == template.source {
                    continue
                }
                guard existing.contains(template.marker) else {
                    throw HooksError.fileSystemError(
                        reason: "Existing non-Cocxy OpenCode plugin at \(url.path); refusing to overwrite."
                    )
                }
                try backupPluginIfNeeded(at: url)
            }

            try fileManager.createDirectory(at: pluginsDirectoryURL, withIntermediateDirectories: true)
            try template.source.write(to: url, atomically: true, encoding: .utf8)
            wroteAny = true
        }

        return HooksInstallResult(
            installed: wroteAny,
            alreadyInstalled: !wroteAny,
            hookEvents: Self.hookEvents
        )
    }

    func uninstallHooks() throws -> HooksUninstallResult {
        var removed = false

        for template in Self.pluginTemplates {
            let url = pluginURL(for: template)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            let existing = try readPlugin(at: url)
            guard existing.contains(template.marker) else {
                throw HooksError.fileSystemError(
                    reason: "Existing non-Cocxy OpenCode plugin at \(url.path); refusing to remove."
                )
            }

            try fileManager.removeItem(at: url)
            removed = true
        }

        return HooksUninstallResult(
            uninstalled: removed,
            nothingToRemove: !removed,
            removedEvents: removed ? Self.hookEvents : []
        )
    }

    func hooksStatus() throws -> HooksStatusResult {
        let installedTemplates = try Self.pluginTemplates.filter { template in
            let url = pluginURL(for: template)
            guard fileManager.fileExists(atPath: url.path) else {
                return false
            }
            let existing = try readPlugin(at: url)
            return existing.contains(template.marker) && existing.contains("hook-handler")
        }

        guard installedTemplates.count == Self.pluginTemplates.count else {
            return HooksStatusResult(installed: false, installedEvents: [])
        }

        return HooksStatusResult(installed: true, installedEvents: Self.hookEvents)
    }

    func dryRun(remove: Bool) -> String {
        let action = remove ? "would remove" : "would install"
        let paths = Self.pluginTemplates
            .map { pluginURL(for: $0).path }
            .joined(separator: ", ")
        return "Dry run: OpenCode \(action) Cocxy \(scopeDescription) plugins at \(paths); no files modified."
    }

    func check() throws -> (line: String, failed: Bool) {
        let missing = try Self.pluginTemplates.compactMap { template -> String? in
            let url = pluginURL(for: template)
            guard fileManager.fileExists(atPath: url.path) else {
                return template.fileName
            }

            let existing = try readPlugin(at: url)
            guard existing.contains(template.marker) else {
                return "\(template.fileName) unmanaged"
            }
            guard existing == template.source else {
                return "\(template.fileName) differs"
            }
            return nil
        }

        guard missing.isEmpty else {
            return ("OpenCode: \(scopeDescription) plugin check failed for \(missing.joined(separator: ", ")).", true)
        }

        return ("OpenCode: \(scopeDescription) plugins OK at \(pluginsDirectoryURL.path).", false)
    }

    func pluginURL(for template: PluginTemplate) -> URL {
        pluginsDirectoryURL.appendingPathComponent(template.fileName)
    }

    private func readPlugin(at url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw HooksError.fileSystemError(
                reason: "Could not read \(url.path): \(error.localizedDescription)"
            )
        }
    }

    private func backupPluginIfNeeded(at url: URL) throws {
        let backupURL = URL(fileURLWithPath: url.path + ".cocxy-backup")
        guard !fileManager.fileExists(atPath: backupURL.path) else {
            return
        }
        try fileManager.copyItem(at: url, to: backupURL)
    }

    static let sessionPluginSource = """
    // \(sessionMarker)
    const COCXY_CLI = process.env.COCXY_CLI || "/Applications/Cocxy Terminal.app/Contents/Resources/cocxy";

    function sessionID(event) {
      return event?.session?.id || event?.sessionID || event?.id || process.env.OPENCODE_SESSION_ID || "";
    }

    async function sendToCocxy(eventName, event, cwd) {
      if (process.env.COCXY_OPENCODE_HOOKS_DISABLED === "1") return;
      if (typeof Bun === "undefined" || !Bun.spawn) return;
      const id = sessionID(event);
      const payload = {
        hook_event_name: eventName,
        session_id: id,
        agent_type: "opencode",
        cwd,
        source_event_type: event?.type || eventName,
      };
      const proc = Bun.spawn([COCXY_CLI, "hook-handler"], {
        stdin: "pipe",
        stdout: "ignore",
        stderr: "ignore",
        env: {
          ...process.env,
          COCXY_CLAUDE_HOOKS: "1",
          COCXY_HOOK_AGENT: "opencode",
          OPENCODE_SESSION_ID: id,
        },
      });
      proc.stdin.write(JSON.stringify(payload));
      proc.stdin.end();
      await proc.exited;
    }

    export const CocxySessionBridge = async ({ directory, worktree }) => {
      const cwd = worktree || directory || process.cwd();
      return {
        "shell.env": async (_input, output) => {
          output.env = {
            ...(output.env || {}),
            COCXY_CLAUDE_HOOKS: "1",
            COCXY_HOOK_AGENT: "opencode",
          };
        },
        event: async ({ event }) => {
          switch (event?.type) {
            case "session.created":
              await sendToCocxy("SessionStart", event, cwd);
              break;
            case "session.idle":
            case "session.deleted":
              await sendToCocxy("Stop", event, cwd);
              break;
            case "session.updated":
            case "message.updated":
              await sendToCocxy("UserPromptSubmit", event, cwd);
              break;
            default:
              break;
          }
        },
        "tool.execute.before": async (input) => {
          await sendToCocxy("PreToolUse", { type: "tool.execute.before", tool: input?.tool }, cwd);
        },
        "tool.execute.after": async (input) => {
          await sendToCocxy("PostToolUse", { type: "tool.execute.after", tool: input?.tool }, cwd);
        },
      };
    };
    """

    static let feedPluginSource = """
    // \(feedMarker)
    const COCXY_CLI = process.env.COCXY_CLI || "/Applications/Cocxy Terminal.app/Contents/Resources/cocxy";

    function sessionID(event) {
      return event?.session?.id || event?.sessionID || event?.id || process.env.OPENCODE_SESSION_ID || "";
    }

    async function sendToCocxy(eventName, event, cwd) {
      if (process.env.COCXY_OPENCODE_HOOKS_DISABLED === "1") return;
      if (typeof Bun === "undefined" || !Bun.spawn) return;
      const id = sessionID(event);
      const payload = {
        hook_event_name: eventName,
        session_id: id,
        agent_type: "opencode",
        cwd,
        source_event_type: event?.type || eventName,
        input: event?.input || event?.text || event?.command || "",
      };
      const proc = Bun.spawn([COCXY_CLI, "hook-handler"], {
        stdin: "pipe",
        stdout: "ignore",
        stderr: "ignore",
        env: {
          ...process.env,
          COCXY_CLAUDE_HOOKS: "1",
          COCXY_HOOK_AGENT: "opencode",
          OPENCODE_SESSION_ID: id,
        },
      });
      proc.stdin.write(JSON.stringify(payload));
      proc.stdin.end();
      await proc.exited;
    }

    export const CocxyFeedBridge = async ({ directory, worktree }) => {
      const cwd = worktree || directory || process.cwd();
      return {
        "tui.prompt.append": async (input) => {
          await sendToCocxy("UserPromptSubmit", { type: "tui.prompt.append", input }, cwd);
        },
        "tui.command.execute": async (input) => {
          await sendToCocxy("UserPromptSubmit", { type: "tui.command.execute", command: input?.command }, cwd);
        },
        event: async ({ event }) => {
          switch (event?.type) {
            case "notification.created":
            case "permission.requested":
              await sendToCocxy("Notification", event, cwd);
              break;
            default:
              break;
          }
        },
      };
    };
    """
}
