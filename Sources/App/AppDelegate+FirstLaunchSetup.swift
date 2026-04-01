// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+FirstLaunchSetup.swift - Auto-setup CLI symlink and Claude Code hooks on launch.

import Foundation

// MARK: - First Launch Setup

extension AppDelegate {

    /// Performs first-launch setup: CLI symlink and Claude Code hook installation.
    ///
    /// Runs on every launch (not just first) because:
    /// - The symlink may break if the app is moved.
    /// - Hooks may be removed by Claude Code updates.
    /// - Both operations are idempotent and fast.
    func performFirstLaunchSetup() {
        installCLISymlink()
        installClaudeCodeHooks()
    }

    // MARK: - CLI Symlink

    /// Creates a symlink at `/usr/local/bin/cocxy` pointing to the CLI binary
    /// inside the app bundle.
    ///
    /// If `/usr/local/bin/` is not writable (no sudo), falls back to
    /// `~/.local/bin/cocxy`. Both locations are standard on macOS.
    ///
    /// Skips silently if the symlink already exists and points to the correct target.
    private func installCLISymlink() {
        let cliBinaryPath = cliPathInBundle()
        guard let cliBinaryPath, FileManager.default.fileExists(atPath: cliBinaryPath) else {
            return
        }

        let primaryPath = "/usr/local/bin/cocxy"
        let fallbackDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin")
        let fallbackPath = fallbackDir.appendingPathComponent("cocxy").path

        // Try primary location first.
        if createSymlinkIfNeeded(at: primaryPath, target: cliBinaryPath) {
            return
        }

        // Fallback: ~/.local/bin/cocxy (user-writable, no sudo needed).
        createFallbackSymlink(dir: fallbackDir, path: fallbackPath, target: cliBinaryPath)
    }

    /// Returns the path to the `cocxy` CLI binary inside the app bundle.
    private func cliPathInBundle() -> String? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        return "\(resourcePath)/cocxy"
    }

    /// Creates or updates a symlink. Returns true on success.
    @discardableResult
    private func createSymlinkIfNeeded(at symlinkPath: String, target: String) -> Bool {
        let fm = FileManager.default

        // Check if symlink already points to the correct target.
        if let existing = try? fm.destinationOfSymbolicLink(atPath: symlinkPath),
           existing == target {
            return true
        }

        // Remove stale symlink or file if it exists.
        if fm.fileExists(atPath: symlinkPath) {
            try? fm.removeItem(atPath: symlinkPath)
        }

        do {
            try fm.createSymbolicLink(atPath: symlinkPath, withDestinationPath: target)
            return true
        } catch {
            return false
        }
    }

    /// Creates the fallback symlink in ~/.local/bin, creating the directory if needed.
    /// Also adds ~/.local/bin to the user's shell profile if not already in PATH,
    /// so the `cocxy` CLI is discoverable on fresh installations.
    private func createFallbackSymlink(dir: URL, path: String, target: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if createSymlinkIfNeeded(at: path, target: target) {
            addLocalBinToPathIfNeeded()
        }
    }

    /// Appends `export PATH="$HOME/.local/bin:$PATH"` to the user's shell
    /// profile if `~/.local/bin` is not already in PATH.
    ///
    /// Uses `~/.zprofile` for zsh (macOS default) and `~/.bash_profile` for
    /// bash. Only writes if the file doesn't already contain `.local/bin`.
    private func addLocalBinToPathIfNeeded() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let localBin = home.appendingPathComponent(".local/bin").path

        // Skip if already in PATH.
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        if currentPath.contains(localBin) { return }

        let exportLine = "\n# Added by Cocxy Terminal\nexport PATH=\"$HOME/.local/bin:$PATH\"\n"

        // Detect shell to choose the correct profile file.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        let profileName = shellName == "bash" ? ".bash_profile" : ".zprofile"
        let profilePath = home.appendingPathComponent(profileName).path

        // Append only if not already present.
        if let content = try? String(contentsOfFile: profilePath, encoding: .utf8) {
            if content.contains(".local/bin") { return }
            let updated = content + exportLine
            try? updated.write(toFile: profilePath, atomically: true, encoding: .utf8)
        } else {
            // Profile doesn't exist — create it.
            try? exportLine.write(toFile: profilePath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Claude Code Hook Installation

    /// Installs Cocxy hooks into `~/.claude/settings.json` using the full path
    /// to the CLI binary inside the app bundle.
    ///
    /// Uses the absolute path (e.g., `/Applications/Cocxy Terminal.app/Contents/Resources/cocxy`)
    /// instead of bare `cocxy` so hooks work even when the CLI is not in PATH.
    ///
    /// Preserves existing user hooks. Idempotent: skips if already installed.
    private func installClaudeCodeHooks() {
        guard let cliPath = cliPathInBundle(),
              FileManager.default.fileExists(atPath: cliPath) else {
            return
        }

        let hookCommand = "'\(cliPath)' hook-handler"
        let settingsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json").path

        do {
            var settings = readOrCreateSettings(at: settingsPath)
            var hooks = (settings["hooks"] as? [String: Any]) ?? [:]

            let eventTypes = [
                "SessionStart", "SessionEnd", "Stop",
                "PreToolUse", "PostToolUse", "PostToolUseFailure",
                "SubagentStart", "SubagentStop",
                "Notification", "TeammateIdle",
                "TaskCompleted", "UserPromptSubmit"
            ]

            var modified = false

            for eventType in eventTypes {
                var eventHooks = (hooks[eventType] as? [[String: Any]]) ?? []

                // Find ALL cocxy hook entries (not just the first).
                // Previous versions could create duplicates that were never
                // cleaned up, causing each event to be processed N times.
                let cocxyIndices = eventHooks.indices.filter { idx in
                    guard let commands = eventHooks[idx]["hooks"] as? [[String: Any]] else {
                        return false
                    }
                    return commands.contains {
                        guard let cmd = $0["command"] as? String else { return false }
                        return cmd.contains("cocxy") && cmd.contains("hook-handler")
                    }
                }

                if cocxyIndices.isEmpty {
                    // No cocxy hook exists — install exactly one.
                    let entry: [String: Any] = [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": hookCommand]
                        ]
                    ]
                    eventHooks.append(entry)
                    hooks[eventType] = eventHooks
                    modified = true
                } else {
                    // Cocxy hook(s) exist. Keep exactly ONE with the correct
                    // path; remove all duplicates.
                    let correctEntry: [String: Any] = [
                        "matcher": "",
                        "hooks": [
                            ["type": "command", "command": hookCommand]
                        ]
                    ]

                    // Check if the first entry already has the correct command.
                    let firstIdx = cocxyIndices[0]
                    let firstCommands = eventHooks[firstIdx]["hooks"] as? [[String: Any]]
                    let isCorrect = firstCommands?.contains {
                        ($0["command"] as? String) == hookCommand
                    } == true

                    // Remove all cocxy entries (in reverse to preserve indices).
                    for idx in cocxyIndices.reversed() {
                        eventHooks.remove(at: idx)
                    }

                    // Re-add exactly one correct entry.
                    eventHooks.append(correctEntry)
                    hooks[eventType] = eventHooks

                    // Mark modified if we removed duplicates or updated the path.
                    if cocxyIndices.count > 1 || !isCorrect {
                        modified = true
                    }
                }
            }

            guard modified else { return }

            settings["hooks"] = hooks
            writeSettings(settings, to: settingsPath)
        } catch {
            // Fail silently — hook installation is best-effort.
        }
    }

    /// Reads settings.json or returns an empty dictionary if it doesn't exist.
    private func readOrCreateSettings(at path: String) -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    /// Writes settings back to the file, creating the directory if needed.
    private func writeSettings(_ settings: [String: Any], to path: String) {
        let directory = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: directory) {
            try? FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
