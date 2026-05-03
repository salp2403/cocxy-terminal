// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginSandbox.swift - Secure execution environment for plugin scripts.

import Foundation

// MARK: - Plugin Sandbox Error

enum PluginSandboxError: Error, Equatable {
    case scriptOutsidePluginDirectory(String)
    case invalidEnvironmentKey(String)
}

// MARK: - Plugin Execution Plan

struct PluginExecutionPlan: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let currentDirectoryURL: URL
}

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
        let pluginDirectory = URL(fileURLWithPath: scriptPath)
            .deletingLastPathComponent()
            .path
        execute(
            scriptPath: scriptPath,
            environment: environment,
            pluginID: pluginID,
            pluginDirectory: pluginDirectory,
            capabilities: []
        )
    }

    /// Executes a plugin script with an explicit plugin root and capability set.
    func execute(
        scriptPath: String,
        environment: [String: String],
        pluginID: String,
        pluginDirectory: String,
        capabilities: Set<PluginCapability>
    ) {
        executionQueue.async { [timeoutSeconds] in
            let plan: PluginExecutionPlan
            do {
                plan = try self.makeExecutionPlan(
                    scriptPath: scriptPath,
                    environment: environment,
                    pluginID: pluginID,
                    pluginDirectory: pluginDirectory,
                    capabilities: capabilities
                )
            } catch {
                NSLog("[PluginSandbox] Rejected script %@: %@", scriptPath, "\(error)")
                return
            }

            let process = Process()
            process.executableURL = plan.executableURL
            process.arguments = plan.arguments
            process.environment = plan.environment
            process.currentDirectoryURL = plan.currentDirectoryURL

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

    /// Builds the sanitized process launch plan before any script is executed.
    func makeExecutionPlan(
        scriptPath: String,
        environment: [String: String],
        pluginID: String,
        pluginDirectory: String,
        capabilities: Set<PluginCapability>
    ) throws -> PluginExecutionPlan {
        let pluginURL = URL(fileURLWithPath: pluginDirectory, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let scriptURL = URL(fileURLWithPath: scriptPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        let pluginPath = pluginURL.path.hasSuffix("/") ? pluginURL.path : pluginURL.path + "/"
        guard scriptURL.path.hasPrefix(pluginPath) else {
            throw PluginSandboxError.scriptOutsidePluginDirectory(scriptPath)
        }

        var cleanEnvironment: [String: String] = [:]
        for (key, value) in environment {
            guard Self.isAllowedEnvironmentKey(key) else {
                throw PluginSandboxError.invalidEnvironmentKey(key)
            }
            cleanEnvironment[key] = String(value.prefix(8_192))
        }

        cleanEnvironment["COCXY_PLUGIN_ID"] = pluginID
        cleanEnvironment["COCXY_SCRIPT_PATH"] = scriptURL.path
        cleanEnvironment["COCXY_PLUGIN_CAPABILITIES"] = capabilities
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        cleanEnvironment["PATH"] = "/usr/local/bin:/usr/bin:/bin"
        cleanEnvironment["HOME"] = NSHomeDirectory()

        return PluginExecutionPlan(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [scriptURL.path],
            environment: cleanEnvironment,
            currentDirectoryURL: pluginURL
        )
    }

    private static func isAllowedEnvironmentKey(_ key: String) -> Bool {
        key.range(
            of: #"^[A-Z_][A-Z0-9_]{0,63}$"#,
            options: .regularExpression
        ) != nil
    }
}
