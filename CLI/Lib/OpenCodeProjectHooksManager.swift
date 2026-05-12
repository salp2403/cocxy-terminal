// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// OpenCodeProjectHooksManager.swift - Project-local OpenCode plugin bridge.

import Foundation

struct OpenCodeProjectHooksManager {
    static let marker = "Cocxy managed OpenCode session bridge"
    static let relativePluginPath = ".opencode/plugins/cocxy-session.js"

    let projectDirectory: URL
    let fileManager: FileManager

    init(
        projectDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        fileManager: FileManager = .default
    ) {
        self.projectDirectory = projectDirectory
        self.fileManager = fileManager
    }

    var pluginURL: URL {
        projectDirectory.appendingPathComponent(Self.relativePluginPath)
    }

    func install() throws -> String {
        let desired = Self.pluginSource
        if fileManager.fileExists(atPath: pluginURL.path) {
            let existing = try String(contentsOf: pluginURL, encoding: .utf8)
            if existing == desired {
                return "OpenCode: project plugin already installed at \(pluginURL.path)."
            }
            guard existing.contains(Self.marker) else {
                throw HooksError.fileSystemError(
                    reason: "Existing non-Cocxy OpenCode plugin at \(pluginURL.path); refusing to overwrite."
                )
            }
            try backupExistingPluginIfNeeded()
        }

        try fileManager.createDirectory(
            at: pluginURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try desired.write(to: pluginURL, atomically: true, encoding: .utf8)
        return "OpenCode: project plugin installed at \(pluginURL.path)."
    }

    func remove() throws -> String {
        guard fileManager.fileExists(atPath: pluginURL.path) else {
            return "OpenCode: no Cocxy project plugin found at \(pluginURL.path)."
        }

        let existing = try String(contentsOf: pluginURL, encoding: .utf8)
        guard existing.contains(Self.marker) else {
            throw HooksError.fileSystemError(
                reason: "Existing non-Cocxy OpenCode plugin at \(pluginURL.path); refusing to remove."
            )
        }

        try fileManager.removeItem(at: pluginURL)
        return "OpenCode: project plugin removed from \(pluginURL.path)."
    }

    func dryRun(remove: Bool) -> String {
        let action = remove ? "would remove" : "would install"
        return "Dry run: OpenCode \(action) Cocxy project plugin at \(pluginURL.path); no files modified."
    }

    func check() throws -> (line: String, failed: Bool) {
        guard fileManager.fileExists(atPath: pluginURL.path) else {
            return ("OpenCode: project plugin missing at \(pluginURL.path).", true)
        }

        let existing = try String(contentsOf: pluginURL, encoding: .utf8)
        guard existing.contains(Self.marker) else {
            return ("OpenCode: project plugin exists but is not managed by Cocxy.", true)
        }

        guard existing == Self.pluginSource else {
            return ("OpenCode: project plugin is managed by Cocxy but differs from the bundled template.", true)
        }

        return ("OpenCode: project plugin OK at \(pluginURL.path).", false)
    }

    private func backupExistingPluginIfNeeded() throws {
        let backupURL = URL(fileURLWithPath: pluginURL.path + ".cocxy-backup")
        guard !fileManager.fileExists(atPath: backupURL.path) else {
            return
        }
        try fileManager.copyItem(at: pluginURL, to: backupURL)
    }

    static let pluginSource = """
    // \(marker)
    const COCXY_CLI = process.env.COCXY_CLI || "/Applications/Cocxy Terminal.app/Contents/Resources/cocxy";

    function sessionID(event) {
      return event?.session?.id || event?.sessionID || event?.id || process.env.OPENCODE_SESSION_ID || "";
    }

    async function sendToCocxy(eventName, event, cwd) {
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
}
