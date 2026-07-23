// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonDeployer.swift - Deploys cocxyd.sh to remote servers via SFTP.

import Foundation

enum DaemonDeployError: Error, Equatable, LocalizedError {
    case bundledScriptUnavailable
    case remoteUploadNotCommitted(SFTPUploadRecoveryState)
    case remoteUploadCleanupUnconfirmed(SFTPUploadRecoveryState)
    case remoteUploadCommitIndeterminate(SFTPUploadRecoveryState)

    var errorDescription: String? {
        switch self {
        case .bundledScriptUnavailable:
            return "The bundled remote daemon script is unavailable."
        case .remoteUploadNotCommitted(let state):
            return "The remote upload did not commit; inspect "
                + "\(state.stagedPayloadPath ?? state.destinationPath) before retrying."
        case .remoteUploadCleanupUnconfirmed(let state):
            return "The remote upload completed; inspect "
                + "\(state.remoteBackupPath ?? state.stagedPayloadPath ?? state.destinationPath) "
                + "before retrying."
        case .remoteUploadCommitIndeterminate(let state):
            return "The remote upload result for \(state.destinationPath) is uncertain; inspect "
                + "\(state.remoteBackupPath ?? state.stagedPayloadPath ?? state.destinationPath) "
                + "before retrying."
        }
    }
}

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
    static let bundledVersion = "1.1.0"

    /// Remote installation path for the daemon script.
    static let remotePath = "~/.cocxy/cocxyd.sh"

    static let prepareRemoteDirectoryCommand =
        #"test ! -L "$HOME/.cocxy" && umask 077 && mkdir -p "$HOME/.cocxy" && chmod 700 "$HOME/.cocxy""#
    static let secureRemoteScriptCommand =
        #"test -f "$HOME/.cocxy/cocxyd.sh" && test ! -L "$HOME/.cocxy/cocxyd.sh" && chmod 700 "$HOME/.cocxy/cocxyd.sh""#
    static func profileNamespace(_ profileID: UUID) -> String {
        profileID.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func startCommand(profileID: UUID) -> String {
        "sh \(remotePath) start \(profileNamespace(profileID))"
    }

    static func stopCommand(profileID: UUID) -> String {
        "sh \(remotePath) stop \(profileNamespace(profileID))"
    }

    static func pingCommand(profileID: UUID) -> String {
        "sh \(remotePath) ping \(profileNamespace(profileID))"
    }

    static func readRemotePortCommand(profileID: UUID) -> String {
        runtimeFileCommand(profileID: profileID, filename: "cocxyd.port")
    }

    static func readRemoteCapabilityCommand(profileID: UUID) -> String {
        runtimeFileCommand(profileID: profileID, filename: "cocxyd.cap")
    }

    private static func runtimeFileCommand(profileID: UUID, filename: String) -> String {
        #"cat "${XDG_RUNTIME_DIR:-/tmp}/cocxyd-$(id -u)/\#(profileNamespace(profileID))/\#(filename)" 2>/dev/null"#
    }

    private weak var executor: (any DaemonDeployExecuting)?
    private let bundledScriptURL: URL?

    init(
        executor: any DaemonDeployExecuting,
        bundledScriptURL: URL? = Bundle.main.url(forResource: "cocxyd", withExtension: "sh")
    ) {
        self.executor = executor
        self.bundledScriptURL = bundledScriptURL
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
        let scriptPath = try resolvedBundledScriptPath()

        _ = try await executor.executeRemote(
            Self.prepareRemoteDirectoryCommand,
            profileID: profileID
        )

        // Upload script.
        try await executor.uploadFile(
            localPath: scriptPath,
            remotePath: Self.remotePath,
            profileID: profileID
        )
        _ = try await executor.executeRemote(
            Self.secureRemoteScriptCommand,
            profileID: profileID
        )
    }

    private func resolvedBundledScriptPath() throws -> String {
        guard let bundledScriptURL,
              bundledScriptURL.isFileURL else {
            throw DaemonDeployError.bundledScriptUnavailable
        }

        let standardizedURL = bundledScriptURL.standardizedFileURL
        let values: URLResourceValues
        do {
            values = try standardizedURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isReadableKey]
            )
        } catch {
            throw DaemonDeployError.bundledScriptUnavailable
        }

        guard standardizedURL.path.hasPrefix("/"),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              values.isReadable == true else {
            throw DaemonDeployError.bundledScriptUnavailable
        }
        return standardizedURL.path
    }

    // MARK: - Start / Stop

    /// Starts the daemon on the remote server.
    ///
    /// Returns the TCP port the daemon is listening on.
    func start(profileID: UUID) async throws -> Int {
        guard let executor else { throw DaemonProtocolError.connectionLost }
        let output: String
        do {
            output = try await executor.executeRemote(
                Self.startCommand(profileID: profileID),
                profileID: profileID
            )
        } catch let startError {
            guard Self.isRemoteCommandTimeout(startError) else { throw startError }
            do {
                return try await readRemotePort(profileID: profileID)
            } catch {
                throw startError
            }
        }

        // The script publishes this only after its loopback listener is bound.
        if let portLine = output.split(separator: "\n").first(where: { $0.hasPrefix("COCXYD_PORT=") }) {
            let portStr = portLine.dropFirst("COCXYD_PORT=".count)
            if let port = Int(portStr), (1...65_535).contains(port) { return port }
        }

        throw DaemonProtocolError.invalidResponse
    }

    /// Reads the TCP port of an already-running daemon from its port file.
    func readRemotePort(profileID: UUID) async throws -> Int {
        guard let executor else { throw DaemonProtocolError.connectionLost }
        let output = try await executor.executeRemote(
            Self.readRemotePortCommand(profileID: profileID),
            profileID: profileID
        )
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(value), (1...65_535).contains(port) else {
            throw DaemonProtocolError.invalidResponse
        }
        return port
    }

    /// Reads the daemon's private 256-bit capability over the active SSH lease.
    func readRemoteCapability(profileID: UUID) async throws -> String {
        guard let executor else { throw DaemonProtocolError.connectionLost }
        let output = try await executor.executeRemote(
            Self.readRemoteCapabilityCommand(profileID: profileID),
            profileID: profileID
        )
        let capability = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DaemonConnection.isValidCapability(capability) else {
            throw DaemonProtocolError.authenticationFailed
        }
        return capability
    }

    /// Stops the daemon on the remote server.
    func stop(profileID: UUID) async throws {
        guard let executor else { throw DaemonProtocolError.connectionLost }
        do {
            _ = try await executor.executeRemote(
                Self.stopCommand(profileID: profileID),
                profileID: profileID
            )
        } catch let stopError {
            guard Self.isRemoteCommandTimeout(stopError) else { throw stopError }
            let stillRunning: Bool
            do {
                stillRunning = try await isRunning(profileID: profileID)
            } catch {
                throw stopError
            }
            if stillRunning { throw stopError }
        }
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
            Self.pingCommand(profileID: profileID),
            profileID: profileID
        )
        return output.contains("\"pong\":true")
    }

    private static func isRemoteCommandTimeout(_ error: any Error) -> Bool {
        if case .remoteCommandTimedOut = error as? SSHMultiplexerError { return true }
        return false
    }
}
