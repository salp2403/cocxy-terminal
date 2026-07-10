// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHMultiplexer.swift - Manages OpenSSH ControlMaster sessions.

import Darwin
import Foundation

// MARK: - SSH Destination

enum SSHDestinationValidationError: Error, Equatable, Sendable {
    case invalidDestination
}

/// A validated OpenSSH destination that remains data at every process boundary.
///
/// Host aliases intentionally allow underscores and plus signs because OpenSSH
/// config names are not limited to DNS hostname grammar. IPv4 and IPv6 literals
/// receive stricter validation to reject ambiguous address-like values.
struct SSHConnectionDestination: Equatable, Sendable {
    private static let maximumByteCount = 1_024
    private static let nameCharacters = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "._+-")
    )
    private static let zoneCharacters = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "._-")
    )

    let user: String?
    let host: String

    var value: String {
        user.map { "\($0)@\(host)" } ?? host
    }

    init(_ rawValue: String) throws {
        guard !rawValue.isEmpty,
              rawValue.utf8.count <= Self.maximumByteCount,
              rawValue.unicodeScalars.allSatisfy({ scalar in
                  !CharacterSet.whitespacesAndNewlines.contains(scalar)
                      && !CharacterSet.controlCharacters.contains(scalar)
              }) else {
            throw SSHDestinationValidationError.invalidDestination
        }

        let components = rawValue.split(separator: "@", omittingEmptySubsequences: false)
        guard components.count == 1 || components.count == 2 else {
            throw SSHDestinationValidationError.invalidDestination
        }

        let parsedUser = components.count == 2 ? String(components[0]) : nil
        let rawHost = String(components[components.count - 1])
        if let parsedUser {
            try Self.validateUser(parsedUser)
        }

        user = parsedUser
        host = try Self.validateAndNormalizeHost(rawHost)
    }

    init(user: String?, host: String) throws {
        try self.init(user.map { "\($0)@\(host)" } ?? host)
    }

    private static func validateUser(_ user: String) throws {
        guard !user.isEmpty,
              user.first != "-",
              user.unicodeScalars.allSatisfy({ nameCharacters.contains($0) }) else {
            throw SSHDestinationValidationError.invalidDestination
        }
    }

    private static func validateAndNormalizeHost(_ rawHost: String) throws -> String {
        guard !rawHost.isEmpty, rawHost.first != "-" else {
            throw SSHDestinationValidationError.invalidDestination
        }

        let host: String
        if rawHost.first == "[" || rawHost.last == "]" {
            guard rawHost.first == "[", rawHost.last == "]", rawHost.count > 2 else {
                throw SSHDestinationValidationError.invalidDestination
            }
            host = String(rawHost.dropFirst().dropLast())
        } else {
            host = rawHost
        }

        guard !host.isEmpty, host.first != "-" else {
            throw SSHDestinationValidationError.invalidDestination
        }

        if host.contains(":") {
            guard isValidIPv6Literal(host) else {
                throw SSHDestinationValidationError.invalidDestination
            }
            return host
        }

        guard !host.contains("[") && !host.contains("]"),
              host != ".",
              host != "..",
              host.unicodeScalars.allSatisfy({ nameCharacters.contains($0) }) else {
            throw SSHDestinationValidationError.invalidDestination
        }

        let numericAddressCharacters = CharacterSet.decimalDigits.union(
            CharacterSet(charactersIn: ".")
        )
        if host.contains("."),
           host.unicodeScalars.allSatisfy({ numericAddressCharacters.contains($0) }),
           !isCanonicalIPv4Literal(host) {
            throw SSHDestinationValidationError.invalidDestination
        }

        return host
    }

    private static func isCanonicalIPv4Literal(_ value: String) -> Bool {
        var address = in_addr()
        guard value.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else {
            return false
        }

        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else {
            return false
        }
        return String(cString: buffer) == value
    }

    private static func isValidIPv6Literal(_ value: String) -> Bool {
        let address: String
        if let zoneSeparator = value.lastIndex(of: "%") {
            let zone = value[value.index(after: zoneSeparator)...]
            guard !zone.isEmpty,
                  zone.first != "-",
                  zone.unicodeScalars.allSatisfy({ zoneCharacters.contains($0) }) else {
                return false
            }
            address = String(value[..<zoneSeparator])
        } else {
            address = value
        }

        var parsed = in6_addr()
        return address.withCString { inet_pton(AF_INET6, $0, &parsed) } == 1
    }
}

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
enum SSHMultiplexerError: Error, Equatable, LocalizedError {
    case invalidDestination
    case connectionFailed(String)
    case disconnectFailed(String)
    case forwardFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            return "Invalid SSH destination"
        case .connectionFailed(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "SSH connection failed"
        case .disconnectFailed(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "SSH disconnect failed"
        case .forwardFailed(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "SSH port forward failed"
        case .notConnected:
            return "SSH ControlMaster is not connected"
        }
    }
}

// MARK: - SSH Multiplexing Protocol

/// Abstract interface for SSH multiplexing operations.
///
/// Enables dependency injection in orchestrators that depend on SSH
/// connection management.
protocol SSHMultiplexing: Sendable {
    func controlPath(for profile: RemoteConnectionProfile) -> String
    func connect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws
    func newSession(profile: RemoteConnectionProfile) throws -> String
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
    /// - Throws: `SSHMultiplexerError.invalidDestination` for malformed destinations,
    ///   or `SSHMultiplexerError.connectionFailed` if SSH exits with a non-zero code.
    func connect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        let destination = try destination(for: profile)
        try ensureControlPathDirectory(for: profile)

        var arguments = buildBaseArguments(for: profile)
        arguments.append(contentsOf: ["-o", "ControlMaster=auto"])
        arguments.append(contentsOf: ["-o", "ControlPersist=yes"])
        arguments.append(contentsOf: ["-o", "ControlPath=\(controlPath(for: profile))"])
        arguments.append("-f")
        arguments.append("-N")
        arguments.append(contentsOf: ["--", destination.value])

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
    ///
    /// - Throws: `SSHMultiplexerError.invalidDestination` for malformed destinations.
    func newSession(profile: RemoteConnectionProfile) throws -> String {
        let destination = try destination(for: profile)
        var parts: [String] = ["ssh"]
        parts.append("-o ControlMaster=no")
        parts.append("-o ControlPath=\(controlPath(for: profile))")

        if let port = profile.port {
            parts.append("-p \(port)")
        }

        parts.append("--")
        parts.append(destination.value)
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
        let destination = try destination(for: profile)
        var arguments = buildBaseArguments(for: profile)
        arguments.append(contentsOf: [
            "-O", "check",
            "-o", "ControlPath=\(controlPath(for: profile))",
            "--", destination.value,
        ])

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
        let destination = try destination(for: profile)
        var arguments = buildBaseArguments(for: profile)
        arguments.append(contentsOf: [
            "-O", "exit",
            "-o", "ControlPath=\(controlPath(for: profile))",
            "--", destination.value,
        ])

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
        let destination = try destination(for: profile)
        let forwardArgs = forwardArguments(for: forward)
        var arguments = buildBaseArguments(for: profile)
        arguments.append(contentsOf: [
            "-O", "forward",
            "-o", "ControlPath=\(controlPath(for: profile))",
        ] + forwardArgs + ["--", destination.value])

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
        let destination = try destination(for: profile)
        let forwardArgs = forwardArguments(for: forward)
        var arguments = buildBaseArguments(for: profile)
        arguments.append(contentsOf: [
            "-O", "cancel",
            "-o", "ControlPath=\(controlPath(for: profile))",
        ] + forwardArgs + ["--", destination.value])

        let result = try executor.execute(command: "/usr/bin/ssh", arguments: arguments)
        guard result.exitCode == 0 else {
            throw SSHMultiplexerError.forwardFailed(result.stderr)
        }
    }

    // MARK: - Remote Command Execution

    /// Executes a command on the remote host through the ControlMaster session.
    ///
    /// Reuses the existing multiplexed connection to avoid opening a new TCP
    /// session. An option boundary precedes the destination so OpenSSH cannot
    /// reinterpret it as local configuration.
    ///
    /// - Parameters:
    ///   - command: The shell command to run on the remote host.
    ///   - profile: The connection profile whose ControlMaster to use.
    ///   - executor: The process executor for running SSH.
    /// - Returns: The result of the remote command execution.
    /// - Throws: `SSHMultiplexerError.invalidDestination` for malformed destinations,
    ///   or `SSHMultiplexerError.connectionFailed` if the command fails to execute.
    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult {
        let destination = try destination(for: profile)
        var arguments = buildBaseArguments(for: profile)
        arguments.append(contentsOf: [
            "-o", "ControlMaster=no",
            "-o", "ControlPath=\(controlPath(for: profile))",
            "--",
            destination.value,
            command,
        ])

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

        if let strictHostKeyChecking = profile.strictHostKeyChecking {
            arguments.append(contentsOf: ["-o", "StrictHostKeyChecking=\(strictHostKeyChecking)"])
        }

        if let knownHostsFile = profile.knownHostsFile {
            arguments.append(contentsOf: ["-o", "UserKnownHostsFile=\(knownHostsFile)"])
        }

        if let batchMode = profile.batchMode {
            arguments.append(contentsOf: ["-o", "BatchMode=\(batchMode ? "yes" : "no")"])
        }

        if !profile.jumpHosts.isEmpty {
            arguments.append(contentsOf: ["-J", profile.jumpHosts.joined(separator: ",")])
        }

        arguments.append(contentsOf: [
            "-o", "ServerAliveInterval=\(profile.keepAliveInterval)",
        ])

        return arguments
    }

    private func ensureControlPathDirectory(for profile: RemoteConnectionProfile) throws {
        let controlPathURL = URL(fileURLWithPath: controlPath(for: profile))
        let directoryURL = controlPathURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// Returns a validated SSH destination: "user@host" or just "host".
    private func destination(for profile: RemoteConnectionProfile) throws -> SSHConnectionDestination {
        do {
            return try SSHConnectionDestination(user: profile.user, host: profile.host)
        } catch {
            throw SSHMultiplexerError.invalidDestination
        }
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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
