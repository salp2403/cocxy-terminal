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
        let remoteUploader = CocxyDRemoteUploader(executor: deployAdapter)
        let remoteBootstrapper = CocxyDRemoteSSHBootstrapper(
            profileStore: profileStore,
            connectionManager: connectionManager,
            platformDetector: daemonDeployer,
            uploader: remoteUploader
        )

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
        self.tunnelManager = tunnelManager
        self.sshKeyManager = keyManager
        self.daemonDeployAdapter = deployAdapter
        self.cocxydRemoteSSHBootstrapper = remoteBootstrapper

        for controller in allWindowControllers {
            controller.remoteConnectionManager = connectionManager
            controller.remoteProfileStore = profileStore
            controller.tunnelManager = tunnelManager
            controller.sshKeyManager = keyManager
            controller.remotePortScanner = portScanner
        }

        // Browser init-script grants are bound to live remote connection and
        // scanner-owned forward leases. These sinks intentionally stay on the
        // publishing main actor so revocation happens before teardown frees a
        // local port for reuse.
        connectionManager.$connections
            .sink { [weak self] connections in
                let activeProfileIDs = Set(connections.compactMap { profileID, state in
                    if case .connected = state {
                        return profileID
                    }
                    return nil
                })
                for viewModel in self?.allWindowControllers.flatMap({
                    $0.allBrowserViewModels()
                }) ?? [] {
                    viewModel.updateInitScriptRemoteConnectionAvailability(
                        activeConnectionProfileIDs: activeProfileIDs
                    )
                }
            }
            .store(in: &hookCancellables)

        portScanner.$forwardedPortMappings
            .sink { [weak self, weak portScanner] forwardedPortMappings in
                let scanningProfileID = portScanner?.scanningProfileID
                for viewModel in self?.allWindowControllers.flatMap({
                    $0.allBrowserViewModels()
                }) ?? [] {
                    viewModel.updateInitScriptRemoteForwardLeaseAvailability(
                        scanningProfileID: scanningProfileID,
                        forwardedPortMappings: forwardedPortMappings
                    )
                }
            }
            .store(in: &hookCancellables)

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
                    if scanner.scanningProfileID != profileID {
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

    func createDirectory(at path: String) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        try FileManager.default.createDirectory(
            atPath: expandedPath,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: expandedPath
        )
    }

    func removeFile(at path: String) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedPath) else { return }
        try FileManager.default.removeItem(atPath: expandedPath)
    }
}

// MARK: - System SSH Key Executor

/// Production implementation of `SSHKeyExecuting` using real processes.
final class SystemSSHKeyExecutor: SSHKeyExecuting {
    private let askpassExecutableURL: URL?

    init(askpassExecutableURL: URL? = Bundle.main.executableURL) {
        self.askpassExecutableURL = askpassExecutableURL
    }

    func execute(command: String, arguments: [String]) throws -> ProcessResult {
        try run(command: command, arguments: arguments, stdinData: nil, environment: nil)
    }

    func execute(command: String, arguments: [String], stdinData: Data) throws -> ProcessResult {
        guard let askpassExecutableURL,
              FileManager.default.isExecutableFile(atPath: askpassExecutableURL.path) else {
            throw SSHKeyManagerError.generationFailed("Secure SSH passphrase helper is unavailable.")
        }

        var environment = ProcessInfo.processInfo.environment
        environment["SSH_ASKPASS"] = askpassExecutableURL.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["DISPLAY"] = environment["DISPLAY"] ?? "cocxy"
        environment[SSHAskpassContract.environmentKey] = SSHAskpassContract.environmentValue
        return try run(
            command: command,
            arguments: arguments,
            stdinData: stdinData,
            environment: environment
        )
    }

    private func run(
        command: String,
        arguments: [String],
        stdinData: Data?,
        environment: [String: String]?
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdinPipe = stdinData.map { _ in Pipe() }
        process.standardInput = stdinPipe

        try process.run()
        if let stdinData, let stdinPipe {
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                process.terminate()
                process.waitUntilExit()
                throw error
            }
        }
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
