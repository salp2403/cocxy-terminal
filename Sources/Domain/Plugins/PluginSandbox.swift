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
    let kernelSandboxProfile: String?
}

protocol PluginSandboxing: Sendable {
    func execute(
        scriptPath: String,
        environment: [String: String],
        pluginID: String,
        pluginDirectory: String,
        capabilities: Set<PluginCapability>
    )
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
final class PluginSandbox: PluginSandboxing, @unchecked Sendable {

    // MARK: - Configuration

    /// Maximum execution time for a single script (in seconds).
    let timeoutSeconds: TimeInterval

    /// Background queue for script execution.
    private let executionQueue: DispatchQueue
    private let kernelSandboxEnabled: Bool
    private let sandboxExecutor: SandboxExecutor
    private let profileBuilder: SandboxProfileBuilder

    // MARK: - Initialization

    init(
        timeoutSeconds: TimeInterval = 10.0,
        kernelSandboxEnabled: Bool = true,
        sandboxExecutor: SandboxExecutor = SandboxExecutor(),
        profileBuilder: SandboxProfileBuilder = SandboxProfileBuilder()
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.kernelSandboxEnabled = kernelSandboxEnabled
        self.sandboxExecutor = sandboxExecutor
        self.profileBuilder = profileBuilder
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

        let shellPlan = PluginExecutionPlan(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [scriptURL.path],
            environment: cleanEnvironment,
            currentDirectoryURL: pluginURL,
            kernelSandboxProfile: nil
        )

        guard kernelSandboxEnabled else {
            return shellPlan.withEnvironmentValue("COCXY_PLUGIN_SANDBOX_MODE", "legacy-disabled")
        }

        let profile = makeKernelSandboxProfile(
            pluginURL: pluginURL,
            capabilities: capabilities
        )

        do {
            let sandboxedPlan = try sandboxExecutor.launchPlan(
                commandURL: shellPlan.executableURL,
                arguments: shellPlan.arguments,
                profile: profile,
                environment: shellPlan.environment
                    .merging(["COCXY_PLUGIN_SANDBOX_MODE": "kernel"]) { _, new in new },
                currentDirectoryURL: shellPlan.currentDirectoryURL
            )
            return PluginExecutionPlan(
                executableURL: sandboxedPlan.executableURL,
                arguments: sandboxedPlan.arguments,
                environment: sandboxedPlan.environment,
                currentDirectoryURL: sandboxedPlan.currentDirectoryURL,
                kernelSandboxProfile: profile
            )
        } catch let error as SandboxExecutorError {
            switch error {
            case .sandboxExecUnavailable(let path):
                NSLog("[PluginSandbox] sandbox-exec unavailable at %@; using legacy plugin execution for %@",
                      path, pluginID)
                return shellPlan.withEnvironmentValue("COCXY_PLUGIN_SANDBOX_MODE", "legacy-unavailable")
            }
        } catch {
            throw error
        }
    }

    private func makeKernelSandboxProfile(
        pluginURL: URL,
        capabilities: Set<PluginCapability>
    ) -> String {
        var sandboxCapabilities = Set(capabilities.flatMap(\.sandboxCapabilities))
        sandboxCapabilities.insert(.filesystemRead)
        sandboxCapabilities.insert(.processExec)

        let pluginStateURL = pluginURL.appendingPathComponent("state", isDirectory: true)
        let writablePaths = capabilities.contains(.filesystemWrite)
            ? [pluginStateURL]
            : []
        let executableSubpaths = capabilities.contains(.processSpawn)
            ? Self.defaultExecutableSubpaths
            : []

        return profileBuilder.profile(
            capabilities: sandboxCapabilities,
            readablePaths: [pluginURL],
            writablePaths: writablePaths,
            executablePaths: Self.defaultShellExecutables,
            readableLiteralPaths: SandboxProfileBuilder.parentDirectoryLiterals(for: pluginURL),
            executableSubpaths: executableSubpaths,
            includeSystemReadBaseline: true
        )
    }

    private static func isAllowedEnvironmentKey(_ key: String) -> Bool {
        key.range(
            of: #"^[A-Z_][A-Z0-9_]{0,63}$"#,
            options: .regularExpression
        ) != nil
    }

    private static let defaultShellExecutables = [
        URL(fileURLWithPath: "/bin/sh"),
        URL(fileURLWithPath: "/bin/bash"),
        URL(fileURLWithPath: "/private/var/select/sh"),
        URL(fileURLWithPath: "/var/select/sh"),
        URL(fileURLWithPath: "/private/var/select/bash"),
        URL(fileURLWithPath: "/var/select/bash"),
    ]

    private static let defaultExecutableSubpaths = [
        URL(fileURLWithPath: "/bin"),
        URL(fileURLWithPath: "/usr/bin"),
        URL(fileURLWithPath: "/usr/local/bin"),
        URL(fileURLWithPath: "/opt/homebrew/bin"),
    ]
}

private extension PluginExecutionPlan {
    func withEnvironmentValue(_ key: String, _ value: String) -> PluginExecutionPlan {
        var updatedEnvironment = environment
        updatedEnvironment[key] = value
        return PluginExecutionPlan(
            executableURL: executableURL,
            arguments: arguments,
            environment: updatedEnvironment,
            currentDirectoryURL: currentDirectoryURL,
            kernelSandboxProfile: kernelSandboxProfile
        )
    }
}
