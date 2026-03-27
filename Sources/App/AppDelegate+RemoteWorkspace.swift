// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+RemoteWorkspace.swift - Remote workspace service initialization.

import AppKit

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

        let keyFileSystem = DiskSSHKeyFileSystem()
        let keyExecutor = SystemSSHKeyExecutor()
        let keyManager = SSHKeyManager(
            fileSystem: keyFileSystem,
            executor: keyExecutor
        )

        self.remoteConnectionManager = connectionManager
        self.remoteProfileStore = profileStore

        windowController?.remoteConnectionManager = connectionManager
        windowController?.remoteProfileStore = profileStore
        windowController?.tunnelManager = tunnelManager
        windowController?.sshKeyManager = keyManager
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
