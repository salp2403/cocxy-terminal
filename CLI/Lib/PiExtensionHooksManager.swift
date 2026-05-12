// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PiExtensionHooksManager.swift - Global Pi extension hook bridge installer.

import Foundation

struct PiExtensionHooksManager {
    static let marker = "Cocxy managed Pi session bridge"
    static let hookEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"]

    let extensionFilePath: String
    let fileManager: FileManager

    init(
        extensionFilePath: String,
        fileManager: FileManager = .default
    ) {
        self.extensionFilePath = extensionFilePath
        self.fileManager = fileManager
    }

    func installHooks() throws -> HooksInstallResult {
        let desired = Self.extensionSource
        if fileManager.fileExists(atPath: extensionFilePath) {
            let existing = try readExtension()
            if existing == desired {
                return HooksInstallResult(installed: false, alreadyInstalled: true, hookEvents: Self.hookEvents)
            }
            guard existing.contains(Self.marker) else {
                throw HooksError.fileSystemError(
                    reason: "Existing non-Cocxy Pi extension at \(extensionFilePath); refusing to overwrite."
                )
            }
            try createBackupIfNeeded()
        }

        let directory = URL(fileURLWithPath: extensionFilePath).deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try desired.write(to: URL(fileURLWithPath: extensionFilePath), atomically: true, encoding: .utf8)

        return HooksInstallResult(installed: true, alreadyInstalled: false, hookEvents: Self.hookEvents)
    }

    func uninstallHooks() throws -> HooksUninstallResult {
        guard fileManager.fileExists(atPath: extensionFilePath) else {
            return HooksUninstallResult(uninstalled: false, nothingToRemove: true, removedEvents: [])
        }

        let existing = try readExtension()
        guard existing.contains(Self.marker) else {
            throw HooksError.fileSystemError(
                reason: "Existing non-Cocxy Pi extension at \(extensionFilePath); refusing to remove."
            )
        }

        try fileManager.removeItem(at: URL(fileURLWithPath: extensionFilePath))
        return HooksUninstallResult(uninstalled: true, nothingToRemove: false, removedEvents: Self.hookEvents)
    }

    func hooksStatus() throws -> HooksStatusResult {
        guard fileManager.fileExists(atPath: extensionFilePath) else {
            return HooksStatusResult(installed: false, installedEvents: [])
        }

        let existing = try readExtension()
        guard existing.contains(Self.marker), existing.contains("hook-handler") else {
            return HooksStatusResult(installed: false, installedEvents: [])
        }

        let installedEvents = Self.hookEvents.filter { existing.contains($0) }
        return HooksStatusResult(installed: !installedEvents.isEmpty, installedEvents: installedEvents)
    }

    private func readExtension() throws -> String {
        do {
            return try String(contentsOf: URL(fileURLWithPath: extensionFilePath), encoding: .utf8)
        } catch {
            throw HooksError.fileSystemError(
                reason: "Could not read \(extensionFilePath): \(error.localizedDescription)"
            )
        }
    }

    private func createBackupIfNeeded() throws {
        let backupPath = "\(extensionFilePath).cocxy-backup"
        guard !fileManager.fileExists(atPath: backupPath) else {
            return
        }
        try fileManager.copyItem(
            at: URL(fileURLWithPath: extensionFilePath),
            to: URL(fileURLWithPath: backupPath)
        )
    }

    static let extensionSource = """
    // \(marker)
    import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

    const COCXY_CLI = process.env.COCXY_CLI || "/Applications/Cocxy Terminal.app/Contents/Resources/cocxy";

    function shellQuote(value: string): string {
      return "'" + value.replace(/'/g, "'\\\\''") + "'";
    }

    function sessionID(ctx: ExtensionContext): string {
      return process.env.PI_SESSION_ID || ctx.sessionManager.getSessionFile?.() || "";
    }

    function payloadFor(eventName: string, sourceEvent: string, event: unknown, ctx: ExtensionContext): string {
      const input = event && typeof event === "object" && "input" in event ? (event as { input?: unknown }).input : undefined;
      const toolName = event && typeof event === "object" && "toolName" in event ? (event as { toolName?: unknown }).toolName : undefined;
      return JSON.stringify({
        hook_event_name: eventName,
        agent_type: "pi",
        session_id: sessionID(ctx),
        cwd: ctx.cwd,
        source_event_type: sourceEvent,
        input,
        tool_name: toolName,
      });
    }

    async function sendToCocxy(
      pi: ExtensionAPI,
      eventName: string,
      sourceEvent: string,
      event: unknown,
      ctx: ExtensionContext
    ): Promise<void> {
      if (process.env.COCXY_PI_HOOKS_DISABLED === "1") return;
      const session = sessionID(ctx);
      const payload = shellQuote(payloadFor(eventName, sourceEvent, event, ctx));
      const command = `printf %s ${payload} | COCXY_CLAUDE_HOOKS=1 COCXY_HOOK_AGENT=pi PI_SESSION_ID=${shellQuote(session)} ${shellQuote(COCXY_CLI)} hook-handler`;
      await pi.exec("sh", ["-lc", command], { signal: ctx.signal, timeout: 5000 });
    }

    export default function (pi: ExtensionAPI) {
      pi.on("session_start", async (event, ctx) => {
        await sendToCocxy(pi, "SessionStart", "session_start", event, ctx);
      });
      pi.on("input", async (event, ctx) => {
        await sendToCocxy(pi, "UserPromptSubmit", "input", event, ctx);
      });
      pi.on("tool_call", async (event, ctx) => {
        await sendToCocxy(pi, "PreToolUse", "tool_call", event, ctx);
      });
      pi.on("tool_result", async (event, ctx) => {
        await sendToCocxy(pi, "PostToolUse", "tool_result", event, ctx);
      });
      pi.on("session_shutdown", async (event, ctx) => {
        await sendToCocxy(pi, "Stop", "session_shutdown", event, ctx);
      });
    }
    """
}
