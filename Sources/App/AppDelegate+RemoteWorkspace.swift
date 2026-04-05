// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+RemoteWorkspace.swift - Remote workspace service initialization.

import AppKit
import Combine

// MARK: - Remote Workspace Wiring

/// Extension that initializes and wires the remote workspace subsystem:
/// profile storage, SSH multiplexer, tunnel manager, and connection manager.
///
/// Extracted from AppDelegate to isolate remote workspace service setup
/// from app lifecycle management.
extension AppDelegate {

    /// Initializes remote workspace services and injects them into the window controller.
    ///
    /// Creates the full dependency chain:
    /// 1. `DiskRemoteProfileFileSystem` -- filesystem abstraction for profiles.
    /// 2. `RemoteProfileStore` -- CRUD store backed by JSON files.
    /// 3. `SSHMultiplexer` -- OpenSSH ControlMaster session management.
    /// 4. `SSHTunnelManager` -- active tunnel tracking and conflict detection.
    /// 5. `SystemProcessExecutor` -- process execution for SSH commands.
    /// 6. `RemoteConnectionManager` -- orchestrates connect/disconnect/health.
    /// 7. `SSHKeyManager` -- SSH key listing and generation.
    ///
    /// Must be called AFTER `createMainWindow()` since it injects services
    /// into the window controller.
    func setupRemoteWorkspace() {
        let fileSystem = DiskRemoteProfileFileSystem()
        let profileStore = RemoteProfileStore(fileSystem: fileSystem)
        let multiplexer = SSHMultiplexer()
        let tunnelManager = SSHTunnelManager()
        let executor = SystemProcessExecutor()

        let connectionManager = RemoteConnectionManager(
            multiplexer: multiplexer,
            profileStore: profileStore,
            tunnelManager: tunnelManager,
            executor: executor
        )

        // Proxy manager — optional, zero overhead when unused.
        let proxyManager = ProxyManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: connectionManager
        )
        connectionManager.proxyManager = proxyManager

        // Relay manager — optional, zero overhead when unused.
        let relayManager = RelayManagerImpl(
            tunnelManager: tunnelManager,
            forwarder: connectionManager,
            tokenStore: RelayKeychainStore()
        )
        connectionManager.relayManager = relayManager

        // Daemon manager — optional, zero overhead when unused.
        let deployAdapter = DaemonDeployAdapter(connectionManager: connectionManager, profileStore: profileStore)
        let daemonDeployer = DaemonDeployer(executor: deployAdapter)
        let daemonManager = DaemonManagerImpl(deployer: daemonDeployer)
        connectionManager.daemonManager = daemonManager

        let keyFileSystem = DiskSSHKeyFileSystem()
        let keyExecutor = SystemSSHKeyExecutor()
        let keyManager = SSHKeyManager(
            fileSystem: keyFileSystem,
            executor: keyExecutor
        )

        // Remote port scanner — detects dev servers on SSH-connected hosts.
        let portScanner = RemotePortScanner(
            multiplexer: multiplexer,
            connectionManager: connectionManager
        )

        self.remoteConnectionManager = connectionManager
        self.remoteProfileStore = profileStore
        self.remotePortScanner = portScanner

        windowController?.remoteConnectionManager = connectionManager
        windowController?.remoteProfileStore = profileStore
        windowController?.tunnelManager = tunnelManager
        windowController?.sshKeyManager = keyManager
        windowController?.remotePortScanner = portScanner

        // Auto-start/stop port scanning when managed connections change.
        connectionManager.$connections
            .receive(on: DispatchQueue.main)
            .sink { [weak portScanner] connections in
                guard let scanner = portScanner else { return }

                // Find the first connected profile to scan.
                let connectedProfile = connections.first { _, state in
                    if case .connected = state { return true }
                    return false
                }

                if let (profileID, _) = connectedProfile {
                    if !scanner.isScanning {
                        scanner.startScanning(profileID: profileID)
                    }
                } else {
                    if scanner.isScanning {
                        scanner.stopScanning()
                    }
                }
            }
            .store(in: &hookCancellables)
    }
}

// MARK: - Disk SSH Key File System

/// Production implementation of `SSHKeyFileSystem` using the real filesystem.
final class DiskSSHKeyFileSystem: SSHKeyFileSystem {

    func listDirectory(at path: String) throws -> [String] {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return try FileManager.default.contentsOfDirectory(atPath: expandedPath)
    }

    func fileExists(at path: String) -> Bool {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expandedPath)
    }
}

// MARK: - System SSH Key Executor

/// Production implementation of `SSHKeyExecuting` using real processes.
final class SystemSSHKeyExecutor: SSHKeyExecuting {

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
}

// MARK: - Daemon Deploy Adapter

/// Bridges `DaemonDeployExecuting` to the existing SSH infrastructure.
///
/// Uses `SSHMultiplexer.executeRemoteCommand()` for remote commands
/// and `SFTPClient.upload()` for file transfer.
@MainActor
final class DaemonDeployAdapter: DaemonDeployExecuting {

    private weak var connectionManager: RemoteConnectionManager?
    private let profileStore: RemoteProfileStore?

    init(connectionManager: RemoteConnectionManager, profileStore: RemoteProfileStore?) {
        self.connectionManager = connectionManager
        self.profileStore = profileStore
    }

    func executeRemote(_ command: String, profileID: UUID) async throws -> String {
        guard let manager = connectionManager else {
            throw DaemonProtocolError.connectionLost
        }
        return try await manager.executeRemoteCommand(command, profileID: profileID)
    }

    func uploadFile(localPath: String, remotePath: String, profileID: UUID) async throws {
        guard connectionManager != nil else {
            throw DaemonProtocolError.connectionLost
        }
        // Upload via SFTPClient using the profile's SSH ControlMaster.
        guard let profile = profileStore?.loadProfile(id: profileID) else {
            throw DaemonProtocolError.connectionLost
        }
        let executor = SystemSFTPExecutor()
        let client = SFTPClient(executor: executor)
        try client.upload(
            localPath: localPath,
            remotePath: remotePath,
            on: profile
        )
    }
}

extension RemoteProfileStore {
    /// Loads a single profile by ID.
    func loadProfile(id: UUID) -> RemoteConnectionProfile? {
        try? loadAll().first { $0.id == id }
    }
}
