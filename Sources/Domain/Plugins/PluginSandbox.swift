// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginSandbox.swift - Secure execution environment for plugin scripts.

import Foundation

// MARK: - Plugin Sandbox

/// Executes plugin scripts in a controlled environment.
///
/// ## Security Model
///
/// 1. Scripts run as the current user (no privilege escalation).
/// 2. A timeout prevents runaway scripts from blocking the app.
/// 3. Environment variables are explicitly allowed — no shell inheritance.
/// 4. Scripts cannot read Cocxy's internal state beyond what is passed.
/// 5. Output is captured but not displayed (logged for debugging).
///
/// ## Execution Model
///
/// Scripts are dispatched to a serial background queue to prevent
/// blocking the main thread. Multiple events are serialized to avoid
/// race conditions between plugin scripts.
final class PluginSandbox: @unchecked Sendable {

    // MARK: - Configuration

    /// Maximum execution time for a single script (in seconds).
    let timeoutSeconds: TimeInterval

    /// Background queue for script execution.
    private let executionQueue: DispatchQueue

    // MARK: - Initialization

    init(timeoutSeconds: TimeInterval = 10.0) {
        self.timeoutSeconds = timeoutSeconds
        self.executionQueue = DispatchQueue(
            label: "com.cocxy.plugin-sandbox",
            qos: .utility
        )
    }

    // MARK: - Execution

    /// Executes a plugin script with the given environment.
    ///
    /// The script is run via `/bin/sh` with:
    /// - A clean environment (only the provided key-value pairs).
    /// - `COCXY_PLUGIN_ID` set to identify the calling plugin.
    /// - A hard timeout that terminates the process if exceeded.
    ///
    /// - Parameters:
    ///   - scriptPath: Absolute path to the script file.
    ///   - environment: Key-value pairs passed as environment variables.
    ///   - pluginID: The plugin that owns this script.
    func execute(
        scriptPath: String,
        environment: [String: String],
        pluginID: String
    ) {
        executionQueue.async { [timeoutSeconds] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [scriptPath]

            // Build a clean environment with only explicit variables.
            var env = environment
            env["COCXY_PLUGIN_ID"] = pluginID
            env["COCXY_SCRIPT_PATH"] = scriptPath
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin"
            env["HOME"] = NSHomeDirectory()
            process.environment = env

            // Capture output for debugging.
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                NSLog("[PluginSandbox] Failed to start script %@: %@",
                      scriptPath, error.localizedDescription)
                return
            }

            // Enforce timeout.
            let deadline = DispatchTime.now() + timeoutSeconds
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if process.isRunning {
                    process.terminate()
                    NSLog("[PluginSandbox] Killed script %@ (timeout after %.0fs)",
                          scriptPath, timeoutSeconds)
                }
            }

            process.waitUntilExit()

            // Log non-zero exit for debugging.
            if process.terminationStatus != 0 {
                let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: stderr, encoding: .utf8) ?? ""
                let truncated = String(errorOutput.prefix(500))
                NSLog("[PluginSandbox] Script %@ exited with code %d: %@",
                      scriptPath, process.terminationStatus, truncated)
            }
        }
    }
}
