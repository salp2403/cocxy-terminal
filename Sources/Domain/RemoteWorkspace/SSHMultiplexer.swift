// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHMultiplexer.swift - Manages OpenSSH ControlMaster sessions.

import Foundation

// MARK: - Process Executor Protocol

/// Abstraction over process execution for testability.
///
/// Production code uses `SystemProcessExecutor`; tests inject a mock
/// that records commands and returns stubbed results.
protocol ProcessExecutor: Sendable {
    func execute(command: String, arguments: [String]) throws -> ProcessResult
    func executeAsync(command: String, arguments: [String]) async throws -> ProcessResult
}

// MARK: - Process Result

/// The result of executing a system process.
struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

// MARK: - Multiplexer Errors

/// Errors that can occur during SSH multiplexing operations.
enum SSHMultiplexerError: Error, Equatable {
    case connectionFailed(String)
    case disconnectFailed(String)
    case forwardFailed(String)
    case notConnected
}

// MARK: - SSH Multiplexing Protocol

/// Abstract interface for SSH multiplexing operations.
///
/// Enables dependency injection in orchestrators that depend on SSH
/// connection management.
protocol SSHMultiplexing: Sendable {
    func controlPath(for profile: RemoteConnectionProfile) -> String
    func connect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws
    func newSession(profile: RemoteConnectionProfile) -> String
    func isAlive(profile: RemoteConnectionProfile, executor: any ProcessExecutor) async throws -> Bool
    func disconnect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws
    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws
    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws

    /// Executes a command on the remote host through the ControlMaster session.
    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult
}

// MARK: - SSH Multiplexer

/// Manages OpenSSH ControlMaster sessions for connection reuse.
///
/// ControlMaster allows multiple SSH sessions to share a single TCP
/// connection, reducing latency for new sessions and enabling dynamic
/// port forwarding via `ssh -O forward`.
///
/// ## Socket Layout
///
/// ```
/// ~/.config/cocxy/sockets/
/// ├── root@server.com:22
/// ├── deploy@staging.com:2222
/// └── admin@db.internal:22
/// ```
struct SSHMultiplexer: SSHMultiplexing, Sendable {

    // MARK: - Control Path

    /// Returns the ControlMaster socket path for the given profile.
    func controlPath(for profile: RemoteConnectionProfile) -> String {
        profile.controlPath
    }

    // MARK: - Connect

    /// Starts a ControlMaster session for the given profile.
    ///
    /// Runs `ssh -o ControlMaster=auto -o ControlPersist=yes -o ControlPath=... -N`
    /// to establish a persistent background connection that subsequent sessions
    /// can reuse.
    ///
    /// - Parameters:
    ///   - profile: The connection profile to use.
    ///   - executor: The process executor for running SSH.
    /// - Throws: `SSHMultiplexerError.connectionFailed` if SSH exits with a non-zero code.
    func connect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        var arguments = buildBaseArguments(for: profile)
        arguments.append(contentsOf: ["-o", "ControlMaster=auto"])
        arguments.append(contentsOf: ["-o", "ControlPersist=yes"])
        arguments.append(contentsOf: ["-o", "ControlPath=\(controlPath(for: profile))"])
        arguments.append("-N")
        arguments.append(destination(for: profile))

        let result = try executor.execute(command: "/usr/bin/ssh", arguments: arguments)
        guard result.exitCode == 0 else {
            throw SSHMultiplexerError.connectionFailed(result.stderr)
        }
    }

    // MARK: - New Session

    /// Returns an SSH command string that reuses the existing ControlMaster.
    ///
    /// The returned command uses `ControlMaster=no` to attach to (not replace)
    /// the existing master session.
    func newSession(profile: RemoteConnectionProfile) -> String {
        var parts: [String] = ["ssh"]
        parts.append("-o ControlMaster=no")
        parts.append("-o ControlPath=\(controlPath(for: profile))")

        if let port = profile.port {
            parts.append("-p \(port)")
        }

        parts.append(destination(for: profile))
        return parts.joined(separator: " ")
    }

    // MARK: - Health Check

    /// Checks whether the ControlMaster session is still alive.
    ///
    /// Runs `ssh -O check` against the control socket.
    ///
    /// - Returns: `true` if the master process is running.
    func isAlive(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> Bool {
        let arguments = [
            "-O", "check",
            "-o", "ControlPath=\(controlPath(for: profile))",
            destination(for: profile),
        ]

        let result = try await executor.executeAsync(
            command: "/usr/bin/ssh", arguments: arguments
        )
        return result.exitCode == 0
    }

    // MARK: - Disconnect

    /// Terminates the ControlMaster session.
    ///
    /// Runs `ssh -O exit` to gracefully shut down the master connection
    /// and remove the control socket.
    func disconnect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        let arguments = [
            "-O", "exit",
            "-o", "ControlPath=\(controlPath(for: profile))",
            destination(for: profile),
        ]

        let result = try executor.execute(command: "/usr/bin/ssh", arguments: arguments)
        guard result.exitCode == 0 else {
            throw SSHMultiplexerError.disconnectFailed(result.stderr)
        }
    }

    // MARK: - Port Forwarding

    /// Dynamically adds a port forward to an active ControlMaster session.
    ///
    /// Runs `ssh -O forward` with the appropriate `-L`, `-R`, or `-D` flag.
    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        let forwardArgs = forwardArguments(for: forward)
        let arguments = [
            "-O", "forward",
            "-o", "ControlPath=\(controlPath(for: profile))",
        ] + forwardArgs + [destination(for: profile)]

        let result = try executor.execute(command: "/usr/bin/ssh", arguments: arguments)
        guard result.exitCode == 0 else {
            throw SSHMultiplexerError.forwardFailed(result.stderr)
        }
    }

    /// Cancels a port forward on an active ControlMaster session.
    ///
    /// Runs `ssh -O cancel` with the same forwarding spec that was used to add it.
    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        let forwardArgs = forwardArguments(for: forward)
        let arguments = [
            "-O", "cancel",
            "-o", "ControlPath=\(controlPath(for: profile))",
        ] + forwardArgs + [destination(for: profile)]

        let result = try executor.execute(command: "/usr/bin/ssh", arguments: arguments)
        guard result.exitCode == 0 else {
            throw SSHMultiplexerError.forwardFailed(result.stderr)
        }
    }

    // MARK: - Remote Command Execution

    /// Executes a command on the remote host through the ControlMaster session.
    ///
    /// Reuses the existing multiplexed connection to avoid opening a new TCP
    /// session. The command is passed via `--` to prevent SSH from interpreting
    /// remote arguments as local flags.
    ///
    /// - Parameters:
    ///   - command: The shell command to run on the remote host.
    ///   - profile: The connection profile whose ControlMaster to use.
    ///   - executor: The process executor for running SSH.
    /// - Returns: The result of the remote command execution.
    /// - Throws: `SSHMultiplexerError.connectionFailed` if the command fails to execute.
    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult {
        let arguments = [
            "-o", "ControlMaster=no",
            "-o", "ControlPath=\(controlPath(for: profile))",
            destination(for: profile),
            "--",
            command,
        ]

        return try await executor.executeAsync(
            command: "/usr/bin/ssh",
            arguments: arguments
        )
    }

    // MARK: - Helpers

    /// Builds the base SSH arguments from a profile (port, identity, etc.).
    private func buildBaseArguments(for profile: RemoteConnectionProfile) -> [String] {
        var arguments: [String] = []

        if let port = profile.port {
            arguments.append(contentsOf: ["-p", "\(port)"])
        }

        if let identityFile = profile.identityFile {
            arguments.append(contentsOf: ["-i", identityFile])
        }

        if !profile.jumpHosts.isEmpty {
            arguments.append(contentsOf: ["-J", profile.jumpHosts.joined(separator: ",")])
        }

        arguments.append(contentsOf: [
            "-o", "ServerAliveInterval=\(profile.keepAliveInterval)",
        ])

        return arguments
    }

    /// Returns the SSH destination string: "user@host" or just "host".
    private func destination(for profile: RemoteConnectionProfile) -> String {
        if let user = profile.user {
            return "\(user)@\(profile.host)"
        }
        return profile.host
    }

    /// Converts a port forward spec into SSH command-line arguments.
    private func forwardArguments(
        for forward: RemoteConnectionProfile.PortForward
    ) -> [String] {
        switch forward {
        case let .local(localPort, remotePort, remoteHost):
            return ["-L", "\(localPort):\(remoteHost):\(remotePort)"]
        case let .remote(remotePort, localPort, localHost):
            return ["-R", "\(remotePort):\(localHost):\(localPort)"]
        case let .dynamic(localPort):
            return ["-D", "\(localPort)"]
        }
    }
}

// MARK: - System Process Executor

/// Production implementation that runs real system processes.
struct SystemProcessExecutor: ProcessExecutor {

    /// Background queue for async process execution.
    private static let processQueue = DispatchQueue(
        label: "com.cocxy.process-executor",
        qos: .userInitiated
    )

    func execute(command: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    func executeAsync(command: String, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            Self.processQueue.async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: command)
                    process.arguments = arguments

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let result = ProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? ""
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
