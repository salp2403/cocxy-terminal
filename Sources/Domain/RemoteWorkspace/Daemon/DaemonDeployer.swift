// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonDeployer.swift - Deploys cocxyd.sh to remote servers via SFTP.

import Foundation

// MARK: - Remote Platform

/// Platform information detected from the remote server.
struct RemotePlatform: Equatable, Sendable {
    let os: String      // "Linux", "Darwin", "FreeBSD"
    let arch: String    // "x86_64", "aarch64", "arm64"

    /// Parses platform from `uname -s && uname -m` output.
    static func parse(_ output: String) -> RemotePlatform? {
        let lines = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
        guard lines.count >= 2 else {
            // Single-line format: "Linux x86_64" or "Linux\nx86_64"
            let parts = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            guard parts.count >= 2 else { return nil }
            return RemotePlatform(os: String(parts[0]), arch: String(parts[1]))
        }
        return RemotePlatform(
            os: String(lines[0]).trimmingCharacters(in: .whitespaces),
            arch: String(lines[1]).trimmingCharacters(in: .whitespaces)
        )
    }
}

// MARK: - Daemon Deploy Protocol

/// Abstraction for remote command execution during deployment.
@MainActor
protocol DaemonDeployExecuting: AnyObject {
    func executeRemote(_ command: String, profileID: UUID) async throws -> String
    func uploadFile(localPath: String, remotePath: String, profileID: UUID) async throws
}

// MARK: - Daemon Deployer

/// Handles deploying, starting, stopping, and upgrading cocxyd.sh on remote servers.
///
/// Uses SSH remote commands for lifecycle management and SFTP for file upload.
/// The cocxyd.sh script is embedded in the app bundle as a resource.
@MainActor
final class DaemonDeployer {

    /// Current version of the bundled cocxyd.sh script.
    static let bundledVersion = "1.0.0"

    /// Remote installation path for the daemon script.
    static let remotePath = "~/.cocxy/cocxyd.sh"

    private weak var executor: (any DaemonDeployExecuting)?

    init(executor: any DaemonDeployExecuting) {
        self.executor = executor
    }

    // MARK: - Platform Detection

    /// Detects the remote server's OS and architecture.
    func detectPlatform(profileID: UUID) async throws -> RemotePlatform {
        guard let executor else { throw DaemonProtocolError.connectionLost }
        let output = try await executor.executeRemote("uname -s && uname -m", profileID: profileID)
        guard let platform = RemotePlatform.parse(output) else {
            throw DaemonProtocolError.invalidResponse
        }
        return platform
    }

    // MARK: - Deploy

    /// Uploads cocxyd.sh to the remote server and makes it executable.
    func deploy(profileID: UUID) async throws {
        guard let executor else { throw DaemonProtocolError.connectionLost }

        // Ensure directory exists.
        _ = try await executor.executeRemote("mkdir -p ~/.cocxy", profileID: profileID)

        // Upload script.
        guard let scriptPath = Bundle.main.path(forResource: "cocxyd", ofType: "sh") else {
            // Fallback: look in project Resources directory.
            let projectPath = "Resources/cocxyd.sh"
            try await executor.uploadFile(
                localPath: projectPath,
                remotePath: Self.remotePath,
                profileID: profileID
            )
            _ = try await executor.executeRemote("chmod +x \(Self.remotePath)", profileID: profileID)
            return
        }

        try await executor.uploadFile(
            localPath: scriptPath,
            remotePath: Self.remotePath,
            profileID: profileID
        )
        _ = try await executor.executeRemote("chmod +x \(Self.remotePath)", profileID: profileID)
    }

    // MARK: - Start / Stop

    /// Starts the daemon on the remote server.
    ///
    /// Returns the TCP port the daemon is listening on.
    func start(profileID: UUID) async throws -> Int {
        guard let executor else { throw DaemonProtocolError.connectionLost }
        let output = try await executor.executeRemote(
            "sh \(Self.remotePath) start",
            profileID: profileID
        )

        // Parse port from output: "COCXYD_PORT=<port>" or "Daemon started (PID ...)"
        if let portLine = output.split(separator: "\n").first(where: { $0.hasPrefix("COCXYD_PORT=") }) {
            let portStr = portLine.dropFirst("COCXYD_PORT=".count)
            if let port = Int(portStr) { return port }
        }

        throw DaemonProtocolError.invalidResponse
    }

    /// Reads the TCP port of an already-running daemon from its port file.
    func readRemotePort(profileID: UUID) async throws -> String {
        guard let executor else { throw DaemonProtocolError.connectionLost }
        let runtimeDir = "\\${XDG_RUNTIME_DIR:-/tmp}/cocxyd-$(id -u)"
        return try await executor.executeRemote(
            "cat \(runtimeDir)/cocxyd.port 2>/dev/null",
            profileID: profileID
        )
    }

    /// Stops the daemon on the remote server.
    func stop(profileID: UUID) async throws {
        guard let executor else { throw DaemonProtocolError.connectionLost }
        _ = try await executor.executeRemote("sh \(Self.remotePath) stop", profileID: profileID)
    }

    // MARK: - Version Check

    /// Checks the installed daemon version on the remote server.
    func remoteVersion(profileID: UUID) async throws -> String? {
        guard let executor else { throw DaemonProtocolError.connectionLost }
        let output = try await executor.executeRemote(
            "grep '^COCXYD_VERSION=' \(Self.remotePath) 2>/dev/null | cut -d'\"' -f2",
            profileID: profileID
        )
        let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    /// Whether the bundled version is newer than the installed one.
    func needsUpgrade(profileID: UUID) async throws -> Bool {
        guard let remote = try await remoteVersion(profileID: profileID) else {
            return true // Not installed.
        }
        return remote != Self.bundledVersion
    }

    // MARK: - Is Running

    /// Checks if the daemon is currently running on the remote server.
    func isRunning(profileID: UUID) async throws -> Bool {
        guard let executor else { throw DaemonProtocolError.connectionLost }
        let output = try await executor.executeRemote(
            "sh \(Self.remotePath) ping",
            profileID: profileID
        )
        return output.contains("\"pong\":true")
    }
}
